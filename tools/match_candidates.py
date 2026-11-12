#!/usr/bin/env python3
"""Предлагает пары «наша карточка без цены ↔ товар магазина».

ЗАЧЕМ. В каталоге есть карточки справочника без единой цены. Привязать
их автоматически нельзя: справочник брал названия со страниц товаров, а
разбор каталога — из `alt` картинки в списке, и это разные написания
одного товара («Антисептик для дерева 2в1 Акватекс полуматовый Сосна
0,8л» против «СОСТАВ АКВАТЕКС СОСНА 0,8Л»).

ПОЧЕМУ НЕ СШИВАЕМ САМИ. Проверено на живой базе: по нашей карточке
«Dulux Diamond Max Protect мат BW 9л» магазин отдаёт 1 л, 2,5 л и 10 л —
девятилитровой у него нет. Привязать цену десятилитровой банки к
карточке девятилитровой хуже, чем оставить «цена не указана».

ПОЭТОМУ ЗДЕСЬ ТОЛЬКО ПРЕДЛОЖЕНИЯ. Скрипт кладёт кандидатов в
`price_match_candidates`, решение принимает человек во вкладке
«Сопоставление» админки (миграция 0048). До подтверждения в каталоге
не меняется ничего.

ГЛАВНОЕ ПРАВИЛО ОТБОРА — РАЗМЕР. Числа в названии (9л, 60x60, 2,7кг)
сравниваются ТОЧНО: если они не совпали, кандидат не предлагается
вовсе. Именно на этом ломаются все «похожие названия»: «1 л» и «9 л»
различаются одним символом, а это разные товары с разной ценой.

Запуск: SUPABASE_URL=... SUPABASE_KEY=... python3 tools/match_candidates.py
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import price_sync as ps  # noqa: E402  — общий разбор магазинов

API = os.environ.get('SUPABASE_URL', '').rstrip('/')
KEEP = 3          # сколько кандидатов показывать человеку
MIN_SCORE = 0.25  # ниже этого даже на глаза не выносим

# Марки и общие слова ничего не различают: «краска» есть у половины
# каталога. Для похожести берём слова длиннее двух букв.
WORD = re.compile(r'[0-9A-ZА-ЯЁ]{3,}')
# Размеры и объёмы: «9Л», «2,7КГ», «60X60», «0.8Л».
SIZE = re.compile(r'\d+(?:[.,]\d+)?\s*(?:Л|КГ|Г|МЛ|М2|ММ|СМ|М|ШТ)?'
                  r'(?:X\d+(?:[.,]\d+)?)*')


def norm(s):
    s = s.upper().replace('Ё', 'Е')
    # кириллическая «х» между цифрами — это латинская x (60х60 → 60X60)
    s = re.sub(r'(?<=\d)[ХX×*](?=\d)', 'X', s)
    return re.sub(r'\s+', ' ', s).strip()


def words(s):
    return set(WORD.findall(norm(s)))


def sizes(s):
    """Числа с единицами — то, что НЕЛЬЗЯ перепутать."""
    out = set()
    for m in re.finditer(r'(\d+(?:[.,]\d+)?)\s*(Л|КГ|Г|МЛ|ШТ|М2|ММ|СМ)?', norm(s)):
        value, unit = m.group(1).replace(',', '.'), m.group(2) or ''
        try:
            value = ('%g' % float(value))
        except ValueError:
            continue
        out.add(value + unit)
    return out


def score(ours, theirs):
    a, b = words(ours), words(theirs)
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def rest(method, path, body=None, prefer=None):
    import subprocess
    args = ['curl', '-s', '-X', method, '-w', '\n%{http_code}',
            '--max-time', '90', '-H', 'Content-Type: application/json']
    if prefer:
        args += ['-H', f'Prefer: {prefer}']
    key = os.environ.get('SUPABASE_KEY')
    if key:
        args += ['-H', f'apikey: {key}', '-H', f'Authorization: Bearer {key}']
    if body is not None:
        args += ['-d', json.dumps(body, ensure_ascii=False)]
    args.append(f'{API}{path}')
    out = subprocess.run(args, capture_output=True, timeout=120)
    text = out.stdout.decode('utf-8', 'replace')
    raw, _, code = text.rpartition('\n')
    try:
        return (json.loads(raw) if raw.strip() else None), int(code or 0)
    except Exception:
        return raw, int(code or 0)


def main():
    if not API:
        print('::error::Нет SUPABASE_URL')
        return 1

    supplier = next((os.environ.get(e, '').strip()
                     for e in ('PRICE_SYNC_MEGASTROY_ID',
                               'PRICE_SYNC_SUPPLIER_ID')
                     if os.environ.get(e, '').strip()), '')
    if not supplier:
        print('Не задан id поставщика «Мегастрой» — нечего предлагать.')
        return 0

    shop = next(s for s in ps.SHOPS if s['title'] == 'Мегастрой')
    print('читаю каталог магазина...')
    prices = ps.collect(shop)
    print(f'товаров у магазина: {len(prices)}')

    products, c1 = ps.fetch_all('/rest/v1/products?select=id,name&order=id')
    offers, c2 = ps.fetch_all('/rest/v1/offers?select=product_id&order=id')
    if products is None or offers is None:
        print(f'::error::Не прочитать каталог: HTTP {c1}/{c2}')
        return 1

    has_price = {o['product_id'] for o in offers}
    empty = [p for p in products if p['id'] not in has_price]
    print(f'карточек без цены: {len(empty)}')

    # Готовим товары магазина один раз: разбор названий дорогой.
    shop_rows = [(name, row, words(name), sizes(name))
                 for name, row in prices.items()]

    body, no_candidate = [], 0
    for p in empty:
        ours_w, ours_s = words(p['name']), sizes(p['name'])
        if not ours_w:
            continue
        found = []
        for name, row, w, s in shop_rows:
            # Размер обязан совпасть. Это и есть главная защита: «1 л»
            # и «9 л» различаются одним символом, но это разные товары.
            if ours_s and s and ours_s != s:
                continue
            value = len(ours_w & w) / len(ours_w | w)
            if value >= MIN_SCORE:
                found.append((value, name, row))
        if not found:
            no_candidate += 1
            continue
        found.sort(key=lambda x: -x[0])
        for value, name, row in found[:KEEP]:
            body.append({
                'product_id': p['id'],
                'supplier_id': int(supplier),
                'title': name,
                'price': row['price'],
                'url': row.get('url'),
                'score': round(value, 3),
            })

    print(f'предложений подготовлено: {len(body)} | '
          f'карточек без единого кандидата: {no_candidate}')
    if not body:
        return 0

    done = 0
    for part in [body[i:i + 200] for i in range(0, len(body), 200)]:
        # Повторный запуск не плодит одно и то же и не падает на уже
        # предложенных парах: без Prefer PostgREST ответил бы 409 и
        # МОЛЧА не вставил всю пачку целиком.
        _, code = rest('POST', '/rest/v1/price_match_candidates'
                               '?on_conflict=product_id,supplier_id,title',
                       part, prefer='resolution=merge-duplicates')
        if code not in (200, 201, 204):
            print(f'  пачка не прошла: HTTP {code}')
            continue
        done += len(part)
    print(f'в очередь добавлено: {done}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
