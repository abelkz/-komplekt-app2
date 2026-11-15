#!/usr/bin/env python3
"""Синхронизация цен поставщиков, у которых есть открытый каталог.

ЗАЧЕМ. Поставщик, который не ведёт прайс в кабинете, всё равно
обновляет цены у себя на сайте. Эта задача раз в сутки читает его
каталог и переносит цены в его предложения у нас, чтобы в карточке
стояла сегодняшняя цена, а не снятая однажды. Устаревшая цена хуже
отсутствующей: по ней человек приедет в магазин и уедет злым.

ГЛАВНОЕ ОГРАНИЧЕНИЕ, НЕ ТЕХНИЧЕСКОЕ. Цена в приложении всегда чья-то:
она попадает в offers поставщика, и его название видно покупателю.
Поэтому магазин синхронизируется, только если для него явно задан id
поставщика — то есть пока с ним не договорились, его цены никуда не
попадают. Это не перестраховка: выставить чужие цены от чужого имени
без спроса — лучший способ поссориться с тем, кого потом зовёшь
на площадку.

ЧТО ТРОГАЕТ. Только предложения указанных поставщиков. Чужие цены,
карточки, названия и фотографии не меняет никогда. Новых карточек не
заводит: если товара в каталоге нет, строка просто пропускается.

ПОБОЧНОЕ ДЕЙСТВИЕ. Снижение цены — событие: триггер в базе пишет
price_drops и тем, у кого товар в избранном, уходит уведомление.

Запуск: .github/workflows/price-sync.yaml (раз в сутки) или вручную.
"""
import html
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

UA = 'Mozilla/5.0 (compatible; KomplektPriceSync/1.0; +https://komplekt.kz)'
PAUSE = 1.5          # пауза между страницами: чужой сервер не наш
API = os.environ.get('SUPABASE_URL', '').rstrip('/')
DRY = os.environ.get('PRICE_SYNC_DRY_RUN', '').lower() in ('1', 'true', 'yes')


# ─────────────────────────── разбор страниц ───────────────────────────

def norm_name(s):
    return re.sub(r'\s+', ' ', s.upper()).strip()


# Цену у «Мегастроя» отличает ПОРЯДОК атрибутов, а не сам data-value:
#
#   артикул       data-name="Арт." data-value="00000000134"   валюты нет
#   старая цена   data-currency="KZT" data-value="27790"      в strike_block
#   текущая цена  data-value="16674" data-currency="KZT"      кнопка покупки
#
# Пока бралось первое data-value в куске, в каталог уезжал АРТИКУЛ:
# «Краска в/д Star Weiss 7,5кг» стоила у нас 134 ₸ вместо 5190 ₸.
# Ошибка не бросалась в глаза, потому что у товаров с буквенным
# артикулом (ST0034) регулярка его проскакивала и случайно попадала в
# цену — часть каталога была верной. Заметил это владелец приложения,
# открыв карточку рядом с сайтом магазина.
MEGA_BUY = re.compile(r'data-value="([0-9]+(?:\.[0-9]+)?)"\s+data-currency="KZT"')
MEGA_SHOWN = re.compile(r'data-currency="KZT"\s+data-value="([0-9]+(?:\.[0-9]+)?)"')


def megastroy_price(part):
    """Текущая цена товара из его куска разметки, или None.

    Сначала кнопка покупки — она несёт именно ту цену, по которой
    товар кладут в корзину. Если кнопки нет (не в наличии), берём
    показанную цену, пропуская блок зачёркнутой: иначе товар со
    скидкой уехал бы к нам дороже, чем он стоит.
    """
    m = MEGA_BUY.search(part)
    if m:
        return float(m.group(1))
    for block in part.split('price_matrix_wrapper')[1:]:
        if 'strike_block' in block[:40]:
            continue
        m = MEGA_SHOWN.search(block)
        if m:
            return float(m.group(1))
    return None


def parse_megastroy(page):
    """Режем страницу по картинке товара: в куске оказываются название
    (в alt), цена и ссылка на страницу товара.

    Резать по ссылке-миниатюре нельзя, хотя так было бы прямее: часть
    карточек свёрстана иначе, и на странице их 18 вместо 20 — пропажа
    молчаливая, разбор просто вернёт меньше товаров.

    Признак настоящей карточки — блок с артикулом: по картинке в
    кусок попадают и баннеры, и рекомендации, и миниатюры галереи
    (на странице раздела их за три сотни при двадцати товарах).
    """
    rows = {}
    for part in re.split(r'(?=<img[^>]+data-src="/upload/)', page):
        name = re.search(r'alt="([^"]{6,200})"', part)
        if not name or 'article_block' not in part:
            continue
        value = megastroy_price(part)
        if value is None or value <= 0:
            continue
        link = re.search(r'href="(/catalog/[^"]+/\d+/)"', part)
        rows.setdefault(norm_name(html.unescape(name.group(1))), {
            'price': value,
            'in_stock': True,
            'url': 'https://megastroy.kz' + link.group(1) if link else None,
        })
    return rows


CARD_MIR = re.compile(r'<div class="card ">(.*?)(?=<div class="card ">|'
                      r'<div class="pagination|</main)', re.S)


def parse_mirceramiki(page):
    """Карточка целиком в div.card: название, цена со скидкой и наличие."""
    rows = {}
    for block in CARD_MIR.findall(page):
        name = re.search(r'class="card-text-link">([^<]{8,200})<', block)
        # Со скидкой цена в new-price (рядом перечёркнутая old-price),
        # без скидки — в normal-price. Читать только new-price значит
        # терять треть каталога, причём незаметно: ошибки нет, просто
        # товаров меньше.
        price = re.search(r'class="(?:new|normal)-price">([\d\s ]+)', block)
        if not name or not price:
            continue
        digits = re.sub(r'[^\d]', '', price.group(1))
        if not digits:
            continue
        link = re.search(r'href="(https://mirceramiki\.kz/product/[^"]+)"',
                         block)
        rows.setdefault(norm_name(html.unescape(name.group(1))), {
            'price': float(digits),
            'in_stock': 'item-availability true' in block,
            'url': link.group(1) if link else None,
        })
    return rows


def megastroy_page_price(page):
    """Цена со страницы самого товара, или None.

    Только кнопка покупки: на странице товара ниже идут «похожие» и
    «с этим покупают» со своими ценами, и запасной путь из
    megastroy_price() мог бы взять цену соседа.
    """
    m = MEGA_BUY.search(page)
    return float(m.group(1)) if m else None


def mirceramiki_page_price(page):
    """Цена со страницы самого товара, или None. Первая на странице —
    цена этого товара; блоки с другими товарами идут ниже."""
    m = re.search(r'class="(?:new|normal)-price">([\d\s\u00a0]+)', page)
    if not m:
        return None
    digits = re.sub(r'[^\d]', '', m.group(1))
    return float(digits) if digits else None


# Магазин добавляется сюда: разделы, разбор страницы и имя переменной
# с id поставщика. Нет переменной — магазин пропускается молча.
SHOPS = [
    {
        'title': 'Мегастрой',
        'base': 'https://megastroy.kz',
        'env': ('PRICE_SYNC_MEGASTROY_ID', 'PRICE_SYNC_SUPPLIER_ID'),
        'parse': parse_megastroy,
        'page_price': megastroy_page_price,
        'page': lambda s, n: f'{s}?PAGEN_1={n}' if n > 1 else s,
        'pages': 25,
        'sections': [
            '/catalog/keramogranit_i_komplektuyushchie/keramogranit/',
            '/catalog/keramogranit_i_komplektuyushchie/plitka_oblitsovochnaya/',
            '/catalog/napolnye_pokrytiya/laminat/',
            '/catalog/lakokrasochnaya_produktsiya/vodnodispersionnye_kraski/',
            '/catalog/lakokrasochnaya_produktsiya/pokrytiya_dlya_dereva/',
            '/catalog/oboi_dekor_sten_i_potolka/dekorativnye_oboi/',
            '/catalog/elektrotovary_i_osveshchenie/osvetitelnye_pribory/',
            '/catalog/elektrotovary_i_osveshchenie/elektrooborudovanie/',
            '/catalog/santekhnika/smesiteli_dushevye_sistemy/',
            '/catalog/santekhnika/unitazy_i_instalyatsii/',
            '/catalog/santekhnika/rakoviny_umyvalniki_moyki/',
            '/catalog/santekhnika/vanny_i_komplektuyushchie/',
            '/catalog/santekhnika/dushevye_kabiny/',
            '/catalog/dveri/mezhkomnatnye_dveri_i_komplektuyushchie/',
            '/catalog/dveri/metallicheskie_dveri/',
        ],
    },
    {
        'title': 'Мир Керамики',
        'base': 'https://mirceramiki.kz',
        'env': ('PRICE_SYNC_MIRCERAMIKI_ID',),
        'parse': parse_mirceramiki,
        'page_price': mirceramiki_page_price,
        'page': lambda s, n: f'{s}?page={n}' if n > 1 else s,
        'pages': 12,
        'sections': [
            '/catalog/keramogranit',
            '/catalog/keramicheskaya-plitka',
            '/catalog/mozaika',
            '/catalog/smesiteli',
            '/catalog/moiki-i-rakoviny',
            '/catalog/installyaciya',
        ],
    },
]


# ─────────────────────────────── Kaspi ───────────────────────────────
#
# Kaspi устроен иначе, чем магазин: один товар — несколько продавцов,
# у каждого своя цена. Поэтому цены берутся не со страницы раздела, а
# по каждому товару отдельно, из того же JSON, которым сайт наполняет
# карточку. Разбирать разметку не нужно — значит, нечему и молча
# сломаться, как было с `normal-price` у «Мира Керамики».
#
# Поставщики здесь не задаются переменной, а узнаются по пометке в
# `about`: это объявления с площадки, а не магазины, которые к нам
# пришли. Новых поставщиков задача не заводит никогда — появился на
# товаре незнакомый продавец, она только скажет об этом в отчёте.

KASPI_CITY = '710000000'                  # Астана
KASPI_MARK = 'Объявление на Kaspi.kz'
KASPI_UA = ('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/131.0.0.0 Safari/537.36')


# Сколько самых дешёвых продавцов площадки обязаны быть в карточке.
KASPI_TOP = 3
KASPI_ABOUT = (KASPI_MARK + '. Цена и наличие — на стороне площадки, '
               'ссылка ведёт на страницу товара.')


def kaspi_sellers(kaspi_id):
    """ВСЕ продавцы одного товара: {номер продавца: (цена, имя)}.

    Ключ — номер, а не имя. Имя для сопоставления не годится: «Мир
    Керамики» есть и у нас как партнёр, и на Kaspi как продавец, а
    когда объявления развели на отдельного поставщика, имя разошлось —
    и задача решила, что товар сняли с продажи у 50 позиций сразу.
    Номер продавца лежит в offers.supplier_sku с заливки.

    Именно все, а не первая страница. Раньше запрос брал восемь первых,
    и продавец, оказавшийся девятым по цене, считался ушедшим — с него
    снималось наличие, хотя товар он продавал.

    None — запрос не удался.
    """
    found, page = {}, 0
    while page < 10:
        body = json.dumps({'cityId': KASPI_CITY, 'id': kaspi_id,
                           'merchantUID': '', 'limit': 64, 'page': page,
                           'sort': True, 'installationId': '-1'})
        out = curl(['curl', '-s', '--max-time', '45', '-A', KASPI_UA,
                    '-X', 'POST', '-H', 'Content-Type: application/json',
                    '-H', 'Accept: application/json, text/*',
                    '-H', f'X-KS-City: {KASPI_CITY}',
                    '-H', f'Referer: https://kaspi.kz/shop/p/x-{kaspi_id}/',
                    '-b', f'kaspi.storefront.cookie.city={KASPI_CITY}',
                    '-d', body,
                    f'https://kaspi.kz/yml/offer-view/offers/{kaspi_id}'])
        if out is None:
            return None
        try:
            rows = json.loads(out.stdout.decode('utf-8', 'replace'))
        except Exception:
            return None
        batch = rows.get('offers') or []
        for o in batch:
            mid = str(o.get('merchantId') or '').strip()
            price = o.get('price')
            if not mid or not price:
                continue
            price = float(price)
            if mid not in found or price < found[mid][0]:
                found[mid] = (price, str(o.get('merchantName') or '').strip())
        total = rows.get('total') or 0
        if not batch or len(found) >= total:
            break
        page += 1
        time.sleep(PAUSE)
    return found


def sync_kaspi():
    mine, code = fetch_all('/rest/v1/suppliers'
                           '?select=id,name,about,website&order=id')
    if code != 200 or mine is None:
        print(f'::error::Kaspi: поставщики не прочитались, HTTP {code}')
        return
    marked = {s['id'] for s in mine if KASPI_MARK in (s.get('about') or '')}
    if not marked:
        print('Kaspi: ни одного поставщика с пометкой площадки — пропуск.')
        return
    # Имена поставщиков БЕЗ пометки площадки. С ними новому продавцу
    # совпадать нельзя: объявление Kaspi под именем партнёра — это его
    # репутация, отданная чужим ценам (см. историю с «Миром Керамики»).
    partners = {(s.get('name') or '').strip().lower()
                for s in mine if s['id'] not in marked}
    # Номер продавца → наш поставщик. Сначала по адресу его страницы на
    # площадке, ниже дополняется по номерам из предложений.
    by_merchant = {}
    for s in mine:
        if s['id'] in marked:
            m = re.search(r'/merchant/(\d+)/', s.get('website') or '')
            if m:
                by_merchant[m.group(1)] = s['id']

    cards, code = fetch_all('/rest/v1/products?select=id,kaspi_id'
                            '&kaspi_id=not.is.null&order=id')
    if code != 200 or cards is None:
        print(f'::error::Kaspi: карточки не прочитались, HTTP {code}')
        return
    targets = {p['id']: str(p['kaspi_id']) for p in cards if p.get('kaspi_id')}
    print(f'  карточек Kaspi: {len(targets)} | поставщиков площадки: '
          f'{len(marked)}')
    if not targets:
        return

    offers, code = fetch_all('/rest/v1/offers?select=id,product_id,'
                             'supplier_id,price,in_stock,supplier_sku,'
                             'product_url&order=id')
    if code != 200 or offers is None:
        print(f'::error::Kaspi: предложения не прочитались, HTTP {code}')
        return
    # Карточка → номер продавца → наше предложение. Предложения без
    # номера пропускаем: сопоставить их с ответом Kaspi нечем, а
    # угадывать по имени — та самая ошибка, из-за которой 50 позиций
    # разом «снялись с продажи».
    existing, card_url = {}, {}
    for o in offers:
        if o['supplier_id'] in marked and o.get('supplier_sku'):
            mid = str(o['supplier_sku']).strip()
            existing.setdefault(o['product_id'], {})[mid] = o
            by_merchant.setdefault(mid, o['supplier_id'])
            if o.get('product_url'):
                card_url[o['product_id']] = o['product_url']

    updated = same = gone = failed = added = new_sellers = wrong_best = 0
    checked = []    # предложения, чью цену площадка сегодня подтвердила
    for pid, kid in targets.items():
        found = kaspi_sellers(kid)
        time.sleep(PAUSE)
        if found is None:
            failed += 1
            continue
        ours = existing.get(pid, {})
        for mid, (price, _) in found.items():
            offer = ours.get(mid)
            if offer is None:
                continue
            if (abs(float(offer['price']) - price) < 0.005
                    and offer['in_stock']):
                same += 1
                checked.append(offer['id'])
                continue
            if not DRY:
                _, c = rest('PATCH', f"/rest/v1/offers?id=eq.{offer['id']}",
                            {'price': price, 'in_stock': True})
                if c not in (200, 204):
                    failed += 1
                    continue
            updated += 1
            checked.append(offer['id'])

        # Самые дешёвые продавцы обязаны быть в карточке.
        #
        # При заливке на товар брали двух-трёх продавцов, и задача только
        # обновляла их цены. Но продавцы на площадке меняются: появляются
        # новые и дешевле. Карточка продолжала называть «лучшей ценой»
        # 39 193 ₸, когда на Kaspi тот же товар стоил 37 150 ₸ у двух
        # продавцов, которых у нас не было. Заметил владелец приложения,
        # открыв карточку рядом с площадкой (15.11.2026). Сравнение цен,
        # которое не показывает самую низкую, — хуже, чем его отсутствие.
        best = sorted(found.items(), key=lambda kv: kv[1][0])[:KASPI_TOP]
        if ours and best and best[0][0] not in ours:
            wrong_best += 1
        url = card_url.get(pid)
        for mid, (price, name) in best:
            if mid in ours or not url or not name:
                continue
            sid = by_merchant.get(mid)
            if sid is None:
                # Имя партнёра занимать нельзя — см. partners выше.
                title = name + ' на Kaspi' if name.lower() in partners else name
                if DRY:
                    sid = -1
                else:
                    row, c = rest('POST', '/rest/v1/suppliers', [{
                        'name': title, 'city': 'Астана', 'status': 'active',
                        'verified': False, 'about': KASPI_ABOUT,
                        'website': 'https://kaspi.kz/shop/info/merchant/'
                                   f'{mid}/address-tab/',
                    }], prefer='return=representation')
                    if c not in (200, 201) or not row:
                        failed += 1
                        continue
                    sid = row[0]['id']
                by_merchant[mid] = sid
                new_sellers += 1
            if not DRY:
                row, c = rest('POST', '/rest/v1/offers', [{
                    'product_id': pid, 'supplier_id': sid, 'price': price,
                    'in_stock': True, 'product_url': url,
                    'supplier_sku': mid,
                }], prefer='return=representation')
                if c not in (200, 201) or not row:
                    failed += 1
                    continue
                ours[mid] = row[0]
            added += 1

        # Продавец больше не показывает товар: цену не трогаем, снимаем
        # наличие. Удалять нельзя — завтра он может вернуться, а история
        # цен и избранное привязаны к предложению.
        for mid, offer in ours.items():
            if mid in found or not offer['in_stock']:
                continue
            if not DRY:
                rest('PATCH', f"/rest/v1/offers?id=eq.{offer['id']}",
                     {'in_stock': False})
            gone += 1

    stamped = stamp_checked(checked)
    print(f'  Kaspi: обновлено {updated} | без изменений {same} | '
          f'снято с наличия {gone} | сбоев {failed} | '
          f'отмечено сверенными {stamped}')
    print(f'  Kaspi: самого дешёвого продавца не было в {wrong_best} '
          f'карточках | добавлено предложений {added} | '
          f'из них от новых продавцов-поставщиков {new_sellers}')


def curl(args, timeout=90):
    try:
        return subprocess.run(args, capture_output=True, timeout=timeout)
    except Exception as e:
        print('  сбой запроса:', e)
        return None


def rest(method, path, body=None, prefer=None):
    """Ключ: в CI — из секрета, в сессии разработчика — от прокси."""
    args = ['curl', '-s', '-X', method, '-w', '\n%{http_code}',
            '--max-time', '60', '-H', 'Content-Type: application/json']
    if prefer:
        args += ['-H', f'Prefer: {prefer}']
    key = os.environ.get('SUPABASE_KEY')
    if key:
        args += ['-H', f'apikey: {key}', '-H', f'Authorization: Bearer {key}']
    if body is not None:
        args += ['-d', json.dumps(body, ensure_ascii=False)]
    args.append(f'{API}{path}')
    out = curl(args)
    if out is None:
        return None, 0
    text = out.stdout.decode('utf-8', 'replace')
    raw, _, code = text.rpartition('\n')
    try:
        return (json.loads(raw) if raw.strip() else None), int(code or 0)
    except Exception:
        return raw, int(code or 0)


def stamp_checked(ids):
    """Отмечает, что цена этих предложений сегодня сверена с источником.

    ЗАЧЕМ. В карточке товара стоит «Обновлено N дней назад» — по этой
    строке человек решает, верить ли цене. Берётся она из
    `price_updated_at`, а его двигает только триггер `offers_track_price`
    и только когда цена ИЗМЕНИЛАСЬ. Цена, которую мы проверяем каждый
    день и которая каждый день совпадает, выглядела поэтому заброшенной:
    у «Мира Керамики» все 1260 предложений показывали «неделю назад»,
    хотя сверялись с сайтом накануне. Приложение само говорило о себе
    хуже, чем есть, — и ровно в том месте, где решается вопрос доверия.

    Поэтому подтверждённую цену мы тоже отмечаем сегодняшним числом.
    Смысл поля теперь «цена подтверждена», а не «цена изменилась»; когда
    она менялась, по-прежнему видно в `price_history`.

    ЧЕГО НЕЛЬЗЯ. Отмечать предложение, которое в каталоге источника не
    нашлось. Его дата должна стареть — это единственный честный признак
    того, что товара у продавца, возможно, уже нет.

    Триггеры на это не реагируют: цена не меняется, значит, нет ни
    записи в историю, ни `prev_price`, ни уведомления о снижении.
    """
    if DRY or not ids:
        return 0
    now = datetime.now(timezone.utc).isoformat()
    done = 0
    for i in range(0, len(ids), 100):
        part = ids[i:i + 100]
        _, c = rest('PATCH',
                    '/rest/v1/offers?id=in.(%s)' % ','.join(map(str, part)),
                    {'price_updated_at': now})
        if c in (200, 204):
            done += len(part)
        else:
            print(f'    отметка о сверке не записалась: HTTP {c}')
    return done


def fetch_all(path):
    """Читает таблицу постранично.

    PostgREST отдаёт максимум 1000 строк, и `limit=5000` этого НЕ
    отменяет — лишнее молча отрезается. На этом уже обожглись: задача
    видела 1000 карточек из 1865 и не находила предложения, а
    загрузчик каталога из-за того же предела завёл 41 дубль.
    """
    rows, offset = [], 0
    while True:
        part, code = rest('GET', f'{path}&limit=1000&offset={offset}')
        if code != 200 or not isinstance(part, list):
            return None, code
        rows += part
        if len(part) < 1000:
            return rows, 200
        offset += 1000


def collect(shop):
    found = {}
    for section in shop['sections']:
        previous = None
        for page in range(1, shop['pages'] + 1):
            url = shop['base'] + shop['page'](section, page)
            out = curl(['curl', '-s', '--max-time', '45', '-A', UA, url])
            if out is None:
                break
            rows = shop['parse'](out.stdout.decode('utf-8', 'replace'))
            if not rows:
                break
            # Конец раздела: страница повторила предыдущую. Сравниваем
            # именно страницы, а не накопленный итог: разделы у магазина
            # пересекаются, и «новых имён не прибавилось» — это обычное
            # дело в середине обхода, а не признак конца.
            keys = set(rows)
            if keys == previous:
                break
            previous = keys
            found.update(rows)
            time.sleep(PAUSE)
        print(f'    {section}: всего {len(found)}')
    return found


def fetch_status(url):
    """Страница и код ответа. Код 0 — запрос не состоялся."""
    out = curl(['curl', '-s', '-L', '--max-time', '45', '-A', UA,
                '-w', '\n%{http_code}', url])
    if out is None:
        return 0, ''
    text = out.stdout.decode('utf-8', 'replace')
    body, _, code = text.rpartition('\n')
    try:
        return int(code), body
    except ValueError:
        return 0, body


def recheck_by_page(shop, offers):
    """Сверяет по странице товара то, чего не нашлось в списках разделов.

    ЗАЧЕМ. Обход разделов находит не всё: товар может выпасть из списка,
    остаться за пределами обхода или сменить подпись под картинкой. Такие
    предложения раньше не сверялись вовсе. Проверено 15.11.2026 на 353
    предложениях, не найденных в списках: у 211 страница товара жива и
    цена на ней совпадает с нашей, а у 60 («Мегастрой») страница отдаёт
    404 — товара у магазина больше нет. Именно эти 60 владелец приложения
    и увидел как «ссылка ведёт на сайт, а не на товар»: магазин на месте
    удалённой страницы показывает общий каталог.

    Возвращает (подтверждённые id, сколько цен изменилось, ушедшие).

    Ушедшим считается только ответ 404/410. Любой другой сбой — таймаут,
    403, 5xx — это не «товара нет», а «не знаем»: предложение не трогаем,
    и его дата продолжает стареть.
    """
    page_price = shop.get('page_price')
    confirmed, changed, gone = [], 0, []
    if not page_price:
        return confirmed, changed, gone
    for offer in offers:
        code, body = fetch_status(offer['product_url'])
        time.sleep(PAUSE)
        if code in (404, 410):
            gone.append(offer)
            continue
        if code != 200:
            continue
        price = page_price(body)
        if price is None:
            continue
        ours = float(offer['price'])
        if abs(ours - price) < 0.005:
            confirmed.append(offer['id'])
            continue
        # Цена со страницы — одно число, вынутое регуляркой. Если оно
        # отличается от нашей в разы, вероятнее ошибка разбора, чем
        # настоящая цена: артикул вместо цены уже однажды уезжал в каталог
        # (CLAUDE.md §10). Такое не переносим, а выносим в отчёт.
        if not ours / 3 <= price <= ours * 3:
            print(f'    подозрительная цена, не переношу: предложение '
                  f'{offer["id"]}, у нас {ours:g}, на странице {price:g}')
            continue
        if not DRY:
            _, c = rest('PATCH', f"/rest/v1/offers?id=eq.{offer['id']}",
                        {'price': price})
            if c not in (200, 204):
                continue
        changed += 1
        confirmed.append(offer['id'])
    return confirmed, changed, gone


def sync(shop, supplier, by_name):
    prices = collect(shop)
    print(f'  цен собрано: {len(prices)}')
    if not prices:
        print(f'::warning::{shop["title"]}: не прочитано ни одной цены — '
              f'возможно, изменилась разметка каталога')
        return

    mine, code = fetch_all(f'/rest/v1/offers'
                           f'?select=id,product_id,price,in_stock,product_url'
                           f'&supplier_id=eq.{supplier}&order=id')
    if code != 200 or mine is None:
        print(f'::error::{shop["title"]}: предложения не прочитались, HTTP {code}')
        return
    existing = {o['product_id']: o for o in mine}

    updated = same = unmatched = failed = 0
    checked = []    # предложения, чью цену сайт сегодня подтвердил
    for key, row in prices.items():
        pid = by_name.get(key)
        if pid is None:
            unmatched += 1
            continue
        offer = existing.get(pid)
        if offer is None:
            # Новых предложений не заводим: решение «этот магазин продаёт
            # этот товар» принимается при заливке каталога, а не здесь.
            unmatched += 1
            continue
        # Ссылка на товар меняется редко, но проставить её надо и тем
        # предложениям, что заведены до миграции 0045.
        url_changed = row.get('url') and offer.get('product_url') != row['url']
        if abs(float(offer['price']) - row['price']) < 0.005 and not url_changed:
            same += 1
            checked.append(offer['id'])
            continue
        if not DRY:
            patch = {'price': row['price'], 'in_stock': row['in_stock']}
            if row.get('url'):
                patch['product_url'] = row['url']
            _, c = rest('PATCH', f"/rest/v1/offers?id=eq.{offer['id']}", patch)
            if c not in (200, 204):
                print(f'    цену не обновить, предложение {offer["id"]}: {c}')
                failed += 1
                continue
        updated += 1
        checked.append(offer['id'])

    # Что не нашлось в списках разделов — сверяем по странице товара.
    seen = set(checked)
    missing = [o for o in mine
               if o['id'] not in seen and o.get('product_url')]
    by_page, repriced, gone = recheck_by_page(shop, missing)
    checked += by_page

    # Товара у магазина больше нет: снимаем наличие и убираем ссылку на
    # удалённую страницу. Предложение не удаляем — к нему привязаны
    # избранное и история цен, и товар может вернуться: тогда обход
    # разделов найдёт его и вернёт и наличие, и ссылку.
    #
    # Предохранитель: если «ушло» больше 40% всех предложений магазина,
    # это почти наверняка не товары пропали, а сайт сменил адреса. Снять
    # наличие с половины каталога по такой причине — хуже, чем не снять.
    removed = 0
    if gone and len(gone) > len(mine) * 0.4:
        print(f'::warning::{shop["title"]}: страницы {len(gone)} товаров из '
              f'{len(mine)} отдают 404 — похоже, сайт сменил адреса. '
              f'Наличие не снимаю, нужна проверка руками.')
    else:
        for offer in gone:
            if not DRY:
                _, c = rest('PATCH', f"/rest/v1/offers?id=eq.{offer['id']}",
                            {'in_stock': False, 'product_url': None})
                if c not in (200, 204):
                    continue
            removed += 1

    stamped = stamp_checked(checked)
    print(f'  {shop["title"]}: обновлено {updated} | без изменений {same} | '
          f'нет предложения {unmatched} | сбоев {failed} | '
          f'по странице товара: подтверждено {len(by_page) - repriced}, '
          f'цена изменилась {repriced}, товар снят с сайта {removed} | '
          f'отмечено сверенными {stamped}')


def main():
    if not API:
        print('::error::Нет SUPABASE_URL')
        return 1

    active = []
    for shop in SHOPS:
        supplier = next((os.environ.get(e, '').strip()
                         for e in shop['env'] if os.environ.get(e, '').strip()),
                        '')
        if supplier:
            active.append((shop, supplier))

    kaspi = os.environ.get('PRICE_SYNC_KASPI', '').lower() in ('1', 'true', 'yes')

    if not active and not kaspi:
        print('Ни один магазин не настроен — синхронизация выключена.')
        print('Это предохранитель: цена в каталоге показывается от имени '
              'конкретного продавца, и включать её можно только по '
              'договорённости с ним. Переменные: '
              + ', '.join(e for s in SHOPS for e in s['env'])
              + ', PRICE_SYNC_KASPI')
        return 0

    products, code = fetch_all('/rest/v1/products?select=id,name_norm&order=id')
    if code != 200 or products is None:
        print(f'::error::Не удалось прочитать товары: HTTP {code}')
        return 1
    by_name = {p['name_norm']: p['id'] for p in products if p.get('name_norm')}
    print(f'карточек в каталоге: {len(by_name)}'
          f'{" · ПРОБНЫЙ ПРОГОН" if DRY else ""}')

    for shop, supplier in active:
        print(f'\n{shop["title"]} (поставщик {supplier}):')
        sync(shop, supplier, by_name)

    if kaspi:
        print('\nKaspi.kz (объявления площадки):')
        sync_kaspi()
    return 0


if __name__ == '__main__':
    sys.exit(main())
