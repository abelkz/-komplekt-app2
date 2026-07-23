-- ============================================================================
-- 0013. Общий каталог: одна карточка товара — много предложений.
--
-- ЧТО ЧИНИМ:
--   Каждый поставщик создавал СВОЮ карточку товара со своим фото. Два
--   продавца одного керамогранита давали две отдельные карточки с одной
--   ценой в каждой — сравнивать нечего, а сравнение цен и есть смысл
--   приложения.
--
-- КАК ДОЛЖНО БЫТЬ:
--   products — карточка каталога: название, фото, бренд, АРТИКУЛ
--              ПРОИЗВОДИТЕЛЯ. Одна на весь каталог.
--   offers   — предложение поставщика: цена, наличие и ЕГО ВНУТРЕННИЙ КОД.
--
--   Ключ объединения — заводской артикул: у Kerama Marazzi это DD640200R,
--   он одинаковый у всех продавцов. Внутренние коды поставщиков разные,
--   поэтому им нужно отдельное поле.
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────
-- 1. Внутренний код поставщика — у предложения
-- ─────────────────────────────────────────────────────────────────────
alter table public.offers
  add column if not exists supplier_sku text;

comment on column public.offers.supplier_sku is
  'Внутренний код товара у поставщика — по нему он обновляет свой прайс';

comment on column public.products.sku is
  'Артикул производителя (заводской) — по нему карточки объединяются';

-- ─────────────────────────────────────────────────────────────────────
-- 2. Переносим коды, которые кабинет записал не туда
--
--    Товары, созданные через кабинет, хранят код поставщика в
--    products.sku. Копируем его в предложение владельца. Сам
--    products.sku не трогаем: вдруг там всё-таки заводской артикул —
--    поставщик поправит карточку сам.
-- ─────────────────────────────────────────────────────────────────────
update public.offers o
   set supplier_sku = p.sku
  from public.products p
 where o.product_id = p.id
   and o.supplier_sku is null
   and p.sku is not null
   and p.owner_id is not null
   and p.owner_id = o.owner_id;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Уникальность артикулов
--
--    Старый индекс требовал уникальности «поставщик + код» — это про
--    прежнюю модель, где у каждого была своя карточка. Теперь уникален
--    заводской артикул в пределах марки, а код поставщика — в пределах
--    его предложений.
-- ─────────────────────────────────────────────────────────────────────
drop index if exists public.products_owner_sku_uniq;

do $$
begin
  create unique index if not exists products_brand_sku_uniq
    on public.products (coalesce(brand_id, -1), upper(sku))
    where sku is not null and sku <> '';
exception when unique_violation then
  raise notice 'Есть карточки с одинаковым заводским артикулом — объедините их, потом создайте индекс';
end $$;

do $$
begin
  create unique index if not exists offers_owner_sku_uniq
    on public.offers (owner_id, upper(supplier_sku))
    where owner_id is not null and supplier_sku is not null and supplier_sku <> '';
exception when unique_violation then
  raise notice 'У поставщика есть два предложения с одним кодом — проверьте прайс';
end $$;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Поиск по каталогу для кабинета
--
--    Поставщик перед созданием товара должен увидеть, что карточка уже
--    есть. Функция ищет по названию и заводскому артикулу и сразу
--    говорит, есть ли у этого поставщика своё предложение.
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.catalog_search(p_query text, p_supplier bigint default null)
returns table (
  id bigint,
  name text,
  sku text,
  unit text,
  image_url text,
  category_slug text,
  brand_name text,
  offers_count bigint,
  min_price numeric,
  mine boolean
)
language sql
stable
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
    from public.products p
    left join public.brands b on b.id = p.brand_id
    left join public.offers o on o.product_id = p.id
   where p_query is not null
     and length(btrim(p_query)) >= 2
     and (p.name ilike '%' || btrim(p_query) || '%'
          or p.sku ilike '%' || btrim(p_query) || '%')
   group by p.id, b.name
   order by count(o.id) desc, p.name
   limit 20;
$$;

grant execute on function public.catalog_search(text, bigint) to authenticated;
