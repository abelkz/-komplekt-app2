-- ============================================================
-- КОМПЛЕКТ · 0041 — слияние карточек-дублей
--
-- Зачем. Нормализация (0040) не пускает НОВЫЕ дубли, но те, что уже
-- накопились, разобрать было нечем: инструмента нет, а вручную
-- запросом нельзя — на карточку ссылаются избранное, подборки,
-- отзывы, история цен и очередь уведомлений, и простое
-- `delete from products` унесло бы их каскадом.
--
-- Что делает merge_products: переводит все ссылки на остающуюся
-- карточку, удаляет дубль и запоминает в product_merges, что одна
-- карточка стала другой. Запись нужна не для истории: по старому id
-- приходят избранное, диплинки и Telegram mini-app.
--
-- Проверка администратора через public.profiles (CLAUDE.md §6.1).
--
-- Применять ПОСЛЕ 0040: нужны product_aliases, sku_norm, name_norm.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Журнал слияний
--
-- from_id БЕЗ внешнего ключа: карточки с таким id уже не существует,
-- в этом весь смысл записи. to_id — с каскадом.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.product_merges (
  from_id   bigint primary key,
  to_id     bigint not null references public.products(id) on delete cascade,
  merged_at timestamptz not null default now(),
  merged_by uuid references auth.users(id)
);

create index if not exists product_merges_to_idx
  on public.product_merges (to_id);

alter table public.product_merges enable row level security;

-- Читать можно всем: по этой таблице клиент узнаёт, куда ведёт
-- старая ссылка на товар. Писать — только merge_products.
drop policy if exists product_merges_read on public.product_merges;
create policy product_merges_read on public.product_merges
  for select using (true);

-- ─────────────────────────────────────────────────────────────
-- 2. Перевод ссылок одной таблицы
--
-- Таблиц со ссылкой на товар много, и набор их в живой базе и в
-- схеме «с нуля» разный: в живой есть projects/project_items (их
-- завёл Telegram mini-app), в 0001_init.sql — collections/
-- collection_items. Поэтому каждая таблица проверяется на
-- существование, а не перечисляется жёстко: пропустить таблицу
-- хуже, чем зря проверить — на ней останутся висеть ссылки на
-- удалённую карточку.
--
-- p_identity — колонки, по которым строка «та же самая» (у
-- избранного это пользователь, у подборки — сама подборка).
-- Там стоят ограничения уникальности, поэтому простой update
-- product_id упёрся бы в них: если товар лежит в избранном на
-- ОБЕИХ карточках, перенос даёт дубль пары. Такие строки сначала
-- удаляются — остаётся одна, уже на остающейся карточке.
--
-- SECURITY DEFINER + проверка роли внутри + revoke от public:
-- без этого функция стала бы готовым инструментом переподвязки
-- чужих данных для любого, кто знает её имя.
-- ─────────────────────────────────────────────────────────────
create or replace function public._repoint_product(
  p_table    text,
  p_keep     bigint,
  p_drop     bigint,
  p_identity text[] default array[]::text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ident text := '';
  col   text;
begin
  if not exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin') then
    raise exception 'Только для администратора' using errcode = '42501';
  end if;

  if to_regclass('public.' || quote_ident(p_table)) is null then return; end if;

  if not exists (select 1 from information_schema.columns c
                  where c.table_schema = 'public'
                    and c.table_name = p_table
                    and c.column_name = 'product_id') then
    return;
  end if;

  foreach col in array coalesce(p_identity, array[]::text[]) loop
    if exists (select 1 from information_schema.columns c
                where c.table_schema = 'public'
                  and c.table_name = p_table
                  and c.column_name = col) then
      ident := ident || format(' or k.%I = d.%I', col, col);
    end if;
  end loop;

  -- «false or …» — чтобы не собирать условие из кусков с and/or
  if ident <> '' then
    execute format(
      'delete from public.%I d using public.%I k
        where d.product_id = $1 and k.product_id = $2 and (false %s)',
      p_table, p_table, ident) using p_drop, p_keep;
  end if;

  execute format('update public.%I set product_id = $1 where product_id = $2',
                 p_table) using p_keep, p_drop;
end;
$$;

revoke all on function public._repoint_product(text, bigint, bigint, text[]) from public;

-- ─────────────────────────────────────────────────────────────
-- 3. Слияние
-- ─────────────────────────────────────────────────────────────
create or replace function public.merge_products(p_keep bigint, p_drop bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me         uuid := auth.uid();
  drop_sku   text;
  drop_name  text;
  drop_image text;
  drop_descr text;
  drop_brand bigint;
  drop_raw   text;
begin
  if not exists (select 1 from public.profiles p
                 where p.id = me and p.role = 'admin') then
    raise exception 'Только для администратора' using errcode = '42501';
  end if;

  if p_keep is null or p_drop is null or p_keep = p_drop then
    raise exception 'Нужны две разные карточки' using errcode = '22023';
  end if;

  select p.sku_norm, p.name_norm, p.image_url, p.description, p.brand_id, p.sku
    into drop_sku, drop_name, drop_image, drop_descr, drop_brand, drop_raw
    from public.products p where p.id = p_drop;

  if not found then
    raise exception 'Карточка % не найдена', p_drop using errcode = 'P0002';
  end if;

  if not exists (select 1 from public.products p where p.id = p_keep) then
    raise exception 'Карточка % не найдена', p_keep using errcode = 'P0002';
  end if;

  -- ── Предложения ───────────────────────────────────────────
  -- У поставщика может быть цена на обеих карточках. Оставляем
  -- ДЕШЁВУЮ: именно её видит покупатель, и именно она — ответ на
  -- вопрос «сколько это стоит у него». Ограничение уникальности
  -- (product_id, supplier_id) двух предложений не допустит, поэтому
  -- лишнее удаляется до переноса.
  delete from public.offers d
   using public.offers k
   where d.product_id = p_drop
     and k.product_id = p_keep
     and k.supplier_id = d.supplier_id
     and k.price <= d.price;

  delete from public.offers k
   using public.offers d
   where k.product_id = p_keep
     and d.product_id = p_drop
     and k.supplier_id = d.supplier_id
     and d.price < k.price;

  update public.offers set product_id = p_keep where product_id = p_drop;

  -- ── Всё остальное, что ссылается на товар ─────────────────
  perform public._repoint_product('reviews', p_keep, p_drop, array['user_id']);
  perform public._repoint_product('favorites', p_keep, p_drop,
                                  array['user_id', 'user_tg_id']);
  perform public._repoint_product('project_items', p_keep, p_drop,
                                  array['project_id']);
  perform public._repoint_product('collection_items', p_keep, p_drop,
                                  array['collection_id']);
  perform public._repoint_product('product_images', p_keep, p_drop);
  perform public._repoint_product('price_drops', p_keep, p_drop);
  perform public._repoint_product('price_history', p_keep, p_drop);
  perform public._repoint_product('events', p_keep, p_drop);
  perform public._repoint_product('app_events', p_keep, p_drop);
  perform public._repoint_product('promotions', p_keep, p_drop);
  perform public._repoint_product('boost_orders', p_keep, p_drop);
  perform public._repoint_product('product_aliases', p_keep, p_drop);

  -- Цепочки: если раньше что-то слили в удаляемую карточку,
  -- та ссылка теперь должна вести на остающуюся.
  update public.product_merges set to_id = p_keep where to_id = p_drop;

  delete from public.products where id = p_drop;

  -- ── Остающаяся карточка дополняется ───────────────────────
  -- Только пустые места: заполненное у неё не перетираем, иначе
  -- слияние превратилось бы в подмену карточки. Артикул ставим
  -- после удаления дубля — до него уникальный индекс не дал бы.
  update public.products p
     set image_url   = coalesce(p.image_url, drop_image),
         description = coalesce(p.description, drop_descr),
         brand_id    = coalesce(p.brand_id, drop_brand),
         sku         = coalesce(p.sku, drop_raw)
   where p.id = p_keep;

  -- ── Старые ключи ведут на остающуюся карточку ─────────────
  -- Без этого следующий импорт того же прайса заведёт дубль
  -- заново: артикул в файле не изменился.
  if drop_sku is not null then
    insert into public.product_aliases (product_id, kind, value_norm)
    values (p_keep, 'sku', drop_sku)
    on conflict (kind, value_norm) do nothing;
  end if;

  if drop_name is not null then
    insert into public.product_aliases (product_id, kind, value_norm)
    values (p_keep, 'name', drop_name)
    on conflict (kind, value_norm) do nothing;
  end if;

  insert into public.product_merges (from_id, to_id, merged_by)
  values (p_drop, p_keep, me)
  on conflict (from_id) do update
    set to_id = excluded.to_id,
        merged_at = now(),
        merged_by = excluded.merged_by;
end;
$$;

revoke all on function public.merge_products(bigint, bigint) from public;
grant execute on function public.merge_products(bigint, bigint) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 4. Кандидаты на слияние
--
-- Две группы: один артикул в пределах марки и одно название в
-- пределах категории. Только ТОЧНЫЕ совпадения после нормализации —
-- похожие названия (триграммы) добавим, когда будет что разбирать:
-- на них больше ложных пар, чем настоящих.
--
-- Имена выходных колонок с префиксом dup_ — иначе в plpgsql
-- «column reference is ambiguous» (грабля из 0035).
-- ─────────────────────────────────────────────────────────────
create or replace function public.admin_duplicate_products(p_limit int default 40)
returns table (
  dup_key      text,
  dup_reason   text,
  dup_id       bigint,
  dup_name     text,
  dup_sku      text,
  dup_brand    text,
  dup_category text,
  dup_image    text,
  dup_source   text,
  dup_offers   bigint,
  dup_min_price numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin') then
    raise exception 'Только для администратора' using errcode = '42501';
  end if;

  return query
  with groups as (
    select 'sku:' || p.sku_norm as k, 'Один артикул' as why, p.id as pid
      from public.products p
     where p.sku_norm is not null
       and exists (select 1 from public.products q
                    where q.sku_norm = p.sku_norm
                      and q.id <> p.id
                      and coalesce(q.brand_id, -1) = coalesce(p.brand_id, -1))
    union all
    select 'name:' || coalesce(p.category_slug, '') || '|' || p.name_norm,
           'Одно название', p.id
      from public.products p
     where p.name_norm is not null
       and exists (select 1 from public.products q
                    where q.name_norm = p.name_norm
                      and q.id <> p.id
                      and coalesce(q.category_slug, '')
                          = coalesce(p.category_slug, ''))
  ),
  picked as (
    select g.k from groups g group by g.k
     order by count(*) desc, g.k
     limit greatest(coalesce(p_limit, 40), 1)
  )
  select g.k, g.why, p.id, p.name, p.sku, b.name, p.category_slug,
         p.image_url, p.source,
         (select count(*) from public.offers o where o.product_id = p.id),
         (select min(o.price) from public.offers o where o.product_id = p.id)
    from groups g
    join picked k on k.k = g.k
    join public.products p on p.id = g.pid
    left join public.brands b on b.id = p.brand_id
   order by g.k, p.id;
end;
$$;

revoke all on function public.admin_duplicate_products(int) from public;
grant execute on function public.admin_duplicate_products(int) to authenticated;
