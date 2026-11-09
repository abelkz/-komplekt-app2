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

UA = 'Mozilla/5.0 (compatible; KomplektPriceSync/1.0; +https://komplekt.kz)'
PAUSE = 1.5          # пауза между страницами: чужой сервер не наш
API = os.environ.get('SUPABASE_URL', '').rstrip('/')
DRY = os.environ.get('PRICE_SYNC_DRY_RUN', '').lower() in ('1', 'true', 'yes')


# ─────────────────────────── разбор страниц ───────────────────────────

def norm_name(s):
    return re.sub(r'\s+', ' ', s.upper()).strip()


def parse_megastroy(page):
    """Название лежит в alt картинки, цена — в data-value рядом."""
    rows = {}
    for part in re.split(r'(?=<img[^>]+data-src="/upload/)', page):
        name = re.search(r'alt="([^"]{6,200})"', part)
        price = re.search(r'data-value="([0-9]+(?:\.[0-9]+)?)"', part)
        if not name or not price:
            continue
        value = float(price.group(1))
        if value > 0:
            rows.setdefault(norm_name(html.unescape(name.group(1))),
                            {'price': value, 'in_stock': True})
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
        rows.setdefault(norm_name(html.unescape(name.group(1))), {
            'price': float(digits),
            'in_stock': 'item-availability true' in block,
        })
    return rows


# Магазин добавляется сюда: разделы, разбор страницы и имя переменной
# с id поставщика. Нет переменной — магазин пропускается молча.
SHOPS = [
    {
        'title': 'Мегастрой',
        'base': 'https://megastroy.kz',
        'env': ('PRICE_SYNC_MEGASTROY_ID', 'PRICE_SYNC_SUPPLIER_ID'),
        'parse': parse_megastroy,
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


# ─────────────────────────── вспомогательное ───────────────────────────

def curl(args, timeout=90):
    try:
        return subprocess.run(args, capture_output=True, timeout=timeout)
    except Exception as e:
        print('  сбой запроса:', e)
        return None


def rest(method, path, body=None):
    """Ключ: в CI — из секрета, в сессии разработчика — от прокси."""
    args = ['curl', '-s', '-X', method, '-w', '\n%{http_code}',
            '--max-time', '60', '-H', 'Content-Type: application/json']
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


def sync(shop, supplier, by_name):
    prices = collect(shop)
    print(f'  цен собрано: {len(prices)}')
    if not prices:
        print(f'::warning::{shop["title"]}: не прочитано ни одной цены — '
              f'возможно, изменилась разметка каталога')
        return

    mine, code = rest('GET', f'/rest/v1/offers?select=id,product_id,price'
                             f'&supplier_id=eq.{supplier}&limit=5000')
    if code != 200 or not isinstance(mine, list):
        print(f'::error::{shop["title"]}: предложения не прочитались, HTTP {code}')
        return
    existing = {o['product_id']: o for o in mine}

    updated = same = unmatched = failed = 0
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
        if abs(float(offer['price']) - row['price']) < 0.005:
            same += 1
            continue
        if not DRY:
            _, c = rest('PATCH', f"/rest/v1/offers?id=eq.{offer['id']}",
                        {'price': row['price'], 'in_stock': row['in_stock']})
            if c not in (200, 204):
                print(f'    цену не обновить, предложение {offer["id"]}: {c}')
                failed += 1
                continue
        updated += 1

    print(f'  {shop["title"]}: обновлено {updated} | без изменений {same} | '
          f'нет предложения {unmatched} | сбоев {failed}')


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

    if not active:
        print('Ни один магазин не настроен — синхронизация выключена.')
        print('Это предохранитель: цена в каталоге показывается от имени '
              'конкретного продавца, и включать её можно только по '
              'договорённости с ним. Переменные: '
              + ', '.join(e for s in SHOPS for e in s['env']))
        return 0

    products, code = rest('GET', '/rest/v1/products?select=id,name_norm&limit=5000')
    if code != 200 or not isinstance(products, list):
        print(f'::error::Не удалось прочитать товары: HTTP {code}')
        return 1
    by_name = {p['name_norm']: p['id'] for p in products if p.get('name_norm')}
    print(f'карточек в каталоге: {len(by_name)}'
          f'{" · ПРОБНЫЙ ПРОГОН" if DRY else ""}')

    for shop, supplier in active:
        print(f'\n{shop["title"]} (поставщик {supplier}):')
        sync(shop, supplier, by_name)
    return 0


if __name__ == '__main__':
    sys.exit(main())
