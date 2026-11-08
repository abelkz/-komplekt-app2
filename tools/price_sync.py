#!/usr/bin/env python3
"""Синхронизация цен поставщика, у которого есть открытый каталог.

ЗАЧЕМ. Поставщик, который не ведёт прайс в кабинете, всё равно
обновляет цены у себя на сайте. Эта задача раз в сутки читает его
каталог и переносит цены в его предложения у нас, чтобы в карточке
товара стояла сегодняшняя цена, а не снятая однажды. Устаревшая цена
хуже отсутствующей: по ней человек приедет в магазин и уедет злым.

ГЛАВНОЕ ОГРАНИЧЕНИЕ, НЕ ТЕХНИЧЕСКОЕ. Цена в приложении всегда чья-то:
она попадает в offers поставщика, и его название видно покупателю.
Поэтому задача не запускается, пока явно не указан id поставщика
(PRICE_SYNC_SUPPLIER_ID) — то есть пока с магазином не договорились
о том, что он в каталоге как продавец. Это не перестраховка: выставить
чужие цены от чужого имени без спроса — лучший способ поссориться
с тем, кого потом зовёшь на площадку.

ЧТО ТРОГАЕТ. Только предложения указанного поставщика. Чужие цены,
карточки, названия и фотографии не меняет никогда.

ПОБОЧНОЕ ДЕЙСТВИЕ. Снижение цены — событие: триггер в базе пишет
price_drops и тем, у кого товар в избранном, уходит уведомление.
Это задумано, но означает, что первый запуск на большом каталоге
может разослать много уведомлений сразу.

Запуск: .github/workflows/price-sync.yaml (раз в сутки) или вручную.
"""
import json
import os
import re
import subprocess
import sys
import time

UA = 'Mozilla/5.0 (compatible; KomplektPriceSync/1.0; +https://komplekt.kz)'
BASE = 'https://megastroy.kz'
PAUSE = 1.5          # пауза между страницами: чужой сервер не наш
MAX_PAGES = 25

SECTIONS = [
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
]

API = os.environ.get('SUPABASE_URL', '').rstrip('/')
SUPPLIER = os.environ.get('PRICE_SYNC_SUPPLIER_ID', '').strip()
OWNER = os.environ.get('PRICE_SYNC_OWNER_ID', '').strip()
DRY = os.environ.get('PRICE_SYNC_DRY_RUN', '').lower() in ('1', 'true', 'yes')


def fail(text):
    print(f'::error::{text}')
    sys.exit(1)


def curl(args, timeout=90):
    try:
        return subprocess.run(args, capture_output=True, timeout=timeout)
    except Exception as e:
        print('  сбой запроса:', e)
        return None


def rest(method, path, body=None, extra=None):
    """Ключ не передаём: его подставляет прокси (в CI — заголовок из
    секрета, см. workflow)."""
    args = ['curl', '-s', '-X', method, '-w', '\n%{http_code}',
            '--max-time', '60', '-H', 'Content-Type: application/json']
    key = os.environ.get('SUPABASE_KEY')
    if key:
        args += ['-H', f'apikey: {key}', '-H', f'Authorization: Bearer {key}']
    for h in (extra or []):
        args += ['-H', h]
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


def norm_name(s):
    return re.sub(r'\s+', ' ', s.upper()).strip()


def page_rows(page_html):
    """Название и цена одного товара лежат в соседних узлах карточки:
    режем страницу по началу карточки и берём первую цену в куске."""
    rows = {}
    parts = re.split(r'(?=<img[^>]+data-src="/upload/)', page_html)
    for part in parts:
        name = re.search(r'alt="([^"]{6,200})"', part)
        price = re.search(r'data-value="([0-9]+(?:\.[0-9]+)?)"', part)
        if not name or not price:
            continue
        value = float(price.group(1))
        if value <= 0:
            continue
        rows.setdefault(norm_name(name.group(1)), value)
    return rows


def collect():
    found = {}
    for section in SECTIONS:
        for page in range(1, MAX_PAGES + 1):
            url = BASE + section + (f'?PAGEN_1={page}' if page > 1 else '')
            out = curl(['curl', '-s', '--max-time', '45', '-A', UA, url])
            if out is None:
                break
            rows = page_rows(out.stdout.decode('utf-8', 'replace'))
            if not rows:
                break
            before = len(found)
            found.update(rows)
            time.sleep(PAUSE)
            if len(found) == before:      # страницы пошли по кругу
                break
        print(f'  {section}: всего собрано {len(found)}')
    return found


def main():
    if not API:
        fail('Нет SUPABASE_URL')
    if not SUPPLIER:
        print('PRICE_SYNC_SUPPLIER_ID не задан — синхронизация выключена.')
        print('Это предохранитель: цена в каталоге всегда показывается '
              'от имени конкретного продавца, и включать её можно только '
              'по договорённости с ним.')
        return 0

    prices = collect()
    print('цен собрано:', len(prices))
    if not prices:
        fail('С сайта не удалось прочитать ни одной цены — '
             'возможно, изменилась разметка каталога')

    products, code = rest(
        'GET', '/rest/v1/products?select=id,name_norm&limit=5000')
    if code != 200 or not isinstance(products, list):
        fail(f'Не удалось прочитать товары: HTTP {code}')
    by_name = {p['name_norm']: p['id'] for p in products if p.get('name_norm')}

    mine, code = rest(
        'GET', f'/rest/v1/offers?select=id,product_id,price'
               f'&supplier_id=eq.{SUPPLIER}&limit=5000')
    if code != 200 or not isinstance(mine, list):
        fail(f'Не удалось прочитать предложения: HTTP {code}')
    existing = {o['product_id']: o for o in mine}

    updated = created = same = unmatched = 0
    for key, price in prices.items():
        pid = by_name.get(key)
        if pid is None:
            unmatched += 1
            continue
        offer = existing.get(pid)
        if offer:
            if abs(float(offer['price']) - price) < 0.005:
                same += 1
                continue
            if not DRY:
                _, c = rest('PATCH', f"/rest/v1/offers?id=eq.{offer['id']}",
                            {'price': price, 'in_stock': True})
                if c not in (200, 204):
                    print('  не удалось обновить цену', offer['id'], c)
                    continue
            updated += 1
        else:
            body = {'product_id': pid, 'supplier_id': int(SUPPLIER),
                    'price': price, 'in_stock': True}
            if OWNER:
                body['owner_id'] = OWNER
            if not DRY:
                _, c = rest('POST', '/rest/v1/offers', body)
                if c not in (200, 201, 204):
                    print('  не удалось создать предложение', pid, c)
                    continue
            created += 1

    print(f'{"ПРОБНЫЙ ПРОГОН · " if DRY else ""}'
          f'обновлено: {updated} | добавлено: {created} | '
          f'без изменений: {same} | нет такой карточки: {unmatched}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
