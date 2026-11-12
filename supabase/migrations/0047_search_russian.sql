-- ============================================================================
-- 0047. Поиск, который понимает русский
--
-- ЗАЧЕМ. Поиск сравнивал буквы в букву (`name ilike '%запрос%'`), поэтому
-- множественное число было для него другим словом. Проверено на живой базе:
--
--     «розетка»  → 59 товаров
--     «розетки»  →  4 товара        ← то же самое, но не находится
--     «розетк»   → 69 товаров
--
-- Хуже того, любой запрос из двух слов не находил НИЧЕГО: «смесители для
-- ванны» → 0, потому что такой подстроки в названии нет никогда.
--
-- ПОЧЕМУ НЕ ЗАРАБОТАЛО РАНЬШЕ. Колонка `search_tsv` описана ещё в `0006`,
-- но та миграция собирала её из `coalesce(brand,'')`, а колонки
-- `products.brand` в живой базе НЕТ (CLAUDE.md §6.1) — поэтому `0006`
-- к живой базе не применялась, и полнотекстового поиска не существовало.
-- Здесь колонка не заводится вовсе: индекс строится по выражению, а марка
-- приезжает из `brands` через join в самой функции.
--
-- ЧТО УЧТЕНО, КРОМЕ СЛОВОФОРМ.
--
--   * Незаконченное слово. Человек печатает «розет» и ждёт подсказку, а не
--     пустой экран: каждое слово запроса ищется как начало слова (`:*`).
--   * Размеры. В каталоге пишут `60x60` латинской буквой (21 товар) или
--     `60*60` (7), а на клавиатуре набирают кириллическую «х». Приводим обе
--     стороны к одному виду, иначе «керамогранит 60х60» не находит ничего.
--   * Старое поведение. Условие `ilike` осталось в ИЛИ: что находилось
--     раньше, находится и теперь. Поиск не может стать хуже.
--   * Опечатки. Триграммное сходство (`pg_trgm` стоит с `0001`) ловит
--     «смеситeль» с латинской «e» и подобное.
--
-- ЧЕГО ЭТО НЕ ЛЕЧИТ. Словарь синонимов. «Лампочки» не находят ничего,
-- потому что в каталоге такого слова нет — там «Лампа», а у этих слов
-- разные основы («лампочк» и «ламп»). Это отдельная задача, и решать её
-- надо списком синонимов, а не поиском.
--
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

-- Индекс по выражению, а не по колонке: генерируемая колонка не может
-- сослаться на другую таблицу, а 'russian'::regconfig делает выражение
-- неизменяемым, что индексу и нужно.
create index if not exists products_fts_ru_idx
  on public.products
  using gin (to_tsvector('russian',
               coalesce(name, '') || ' ' || coalesce(sku, '')));

-- Для поиска по кусочку слова и опечаткам.
create index if not exists products_name_trgm_idx
  on public.products using gin (name gin_trgm_ops);


create or replace function public.search_products(
  p_query text,
  p_limit int default 100
)
returns table (
  product_id bigint,
  rank       real
)
language sql
stable
set search_path = public
as $$
  with raw as (
    select btrim(coalesce(p_query, '')) as q
  ),
  norm as (
    -- «60х60» кириллицей → «60x60» латиницей, как пишет каталог
    select q,
           regexp_replace(lower(q), '([0-9])[хх×*]([0-9])', '\1x\2', 'g') as qn
      from raw
  ),
  tq as (
    select n.q, n.qn,
           -- каждое слово — как начало слова; мусор отброшен, поэтому
           -- to_tsquery не споткнётся о скобки и кавычки
           nullif((select string_agg(w || ':*', ' & ')
                     from unnest(regexp_split_to_array(
                            regexp_replace(n.qn, '[^0-9a-zа-яё]+', ' ', 'g'),
                            '\s+')) as w
                    where length(w) > 0), '') as qs
      from norm n
  )
  select p.id,
         greatest(
           case when t.qs is not null
                then ts_rank(to_tsvector('russian',
                               coalesce(p.name,'') || ' ' || coalesce(p.sku,'')),
                             to_tsquery('russian', t.qs))
                else 0 end,
           similarity(p.name, t.q)
         )::real as rank
    from public.products p
    cross join tq t
    left join public.brands b on b.id = p.brand_id
   where length(t.q) >= 2
     and (
       (t.qs is not null
        and to_tsvector('russian',
              coalesce(p.name,'') || ' ' || coalesce(p.sku,''))
            @@ to_tsquery('russian', t.qs))
       or p.name ilike '%' || t.q || '%'
       or p.sku  ilike '%' || t.q || '%'
       or b.name ilike '%' || t.q || '%'
       -- размеры: обе стороны к одному виду
       or regexp_replace(lower(p.name), '[хх×*]', 'x', 'g')
          ilike '%' || regexp_replace(t.qn, '[хх×*]', 'x', 'g') || '%'
       or (length(t.q) >= 4 and similarity(p.name, t.q) > 0.3)
     )
   order by rank desc, p.name
   limit greatest(p_limit, 1);
$$;

revoke all on function public.search_products(text, int) from public;
grant execute on function public.search_products(text, int) to anon, authenticated;

comment on function public.search_products(text, int) is
  'Поиск по каталогу с учётом словоформ русского языка. Ищет по названию, '
  'артикулу и марке; понимает незаконченное слово, размеры через х/x/* '
  'и опечатки. Старое поведение ilike сохранено в ИЛИ — поиск не может '
  'найти меньше, чем раньше';


-- ──────────────────────────────────────────────────────────────────────────
-- Тот же поиск — в кабинете поставщика.
--
-- `catalog_search` (0013) ищет карточку, на которую поставщик ставит свою
-- цену, и искала она так же буква в букву. Это опаснее, чем в каталоге:
-- не нашёл готовую карточку — завёл вторую такую же, и сравнение цен
-- перестаёт работать ровно там, ради чего оно есть. Склейка дублей потом
-- делается руками (вкладка «Дубли», `0041`).
--
-- Сигнатуру не трогаем: её зовёт supplier_cabinet_repository.dart.
-- ──────────────────────────────────────────────────────────────────────────

create or replace function public.catalog_search(
  p_query    text,
  p_supplier bigint default null
)
returns table (
  id            bigint,
  name          text,
  sku           text,
  unit          text,
  image_url     text,
  category_slug text,
  brand_name    text,
  offers_count  bigint,
  min_price     numeric,
  mine          boolean
)
language sql
stable
set search_path = public
as $$
  select p.id,
         p.name,
         p.sku,
         p.unit,
         p.image_url,
         p.category_slug,
         b.name as brand_name,
         count(o.id) as offers_count,
         min(o.price) as min_price,
         bool_or(o.supplier_id = p_supplier) as mine
    from public.search_products(p_query, 20) s
    join public.products p on p.id = s.product_id
    left join public.brands b on b.id = p.brand_id
    left join public.offers o on o.product_id = p.id
   group by p.id, b.name, s.rank
   order by s.rank desc, count(o.id) desc, p.name;
$$;

comment on function public.catalog_search(text, bigint) is
  'Поиск готовой карточки для кабинета поставщика. С 0047 понимает '
  'словоформы — иначе поставщик не находил свой товар и заводил дубль';
