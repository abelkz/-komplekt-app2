-- ============================================================================
-- 0012. История цены и уведомления о снижении.
--
-- ЧТО ЧИНИМ:
--   1. Приложение нигде не показывает, что цена изменилась — сравнивать
--      не с чем: в базе хранится только текущая цена.
--   2. Экран «Уведомления о ценах» всегда пуст: строки в price_drops
--      никто не создаёт. Раньше это должна была делать серверная функция,
--      которой нет.
--
-- РЕШЕНИЕ — два триггера на offers:
--   • перед изменением цены запоминаем прежнюю в prev_price;
--   • после изменения, если цена упала, пишем уведомление каждому,
--      у кого этот товар в избранном и порог снижения пройден.
--
-- Порог берётся из профиля (notify_threshold, миграция 0009). Если
-- колонок ещё нет, считаем порогом 10% и уведомления включёнными.
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────
-- 1. Прежняя цена рядом с текущей
-- ─────────────────────────────────────────────────────────────────────
alter table public.offers
  add column if not exists prev_price numeric(12,2);

comment on column public.offers.prev_price is
  'Цена до последнего изменения — по ней приложение показывает ▼/▲';

-- ─────────────────────────────────────────────────────────────────────
-- 2. Запоминаем прежнюю цену и время изменения
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.offers_track_price()
returns trigger
language plpgsql
as $$
begin
  if new.price is distinct from old.price then
    new.prev_price := old.price;
    new.price_updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists offers_track_price on public.offers;
create trigger offers_track_price
  before update on public.offers
  for each row execute function public.offers_track_price();

-- ─────────────────────────────────────────────────────────────────────
-- 3. Уведомление тем, у кого товар в избранном
--
--    Пишем только при снижении цены и только если процент снижения
--    не меньше порога, выбранного пользователем в настройках.
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.offers_notify_price_drop()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  drop_percent numeric;
  p_name text;
  s_name text;
begin
  if old.price is null or new.price is null or new.price >= old.price then
    return null;                      -- цена не упала — уведомлять не о чем
  end if;

  drop_percent := round((1 - new.price / old.price) * 100);

  select p.name into p_name from public.products p where p.id = new.product_id;
  select s.name into s_name from public.suppliers s where s.id = new.supplier_id;

  insert into public.price_drops
    (user_id, product_id, product_name, supplier_name, old_price, new_price, status)
  select f.user_id,
         new.product_id,
         coalesce(p_name, 'Товар'),
         coalesce(s_name, ''),
         old.price,
         new.price,
         'sent'
    from public.favorites f
    left join public.profiles pr on pr.id = f.user_id
   where f.product_id = new.product_id
     and f.user_id is not null
     and coalesce(pr.notify_price_drops, true)
     and drop_percent >= coalesce(pr.notify_threshold, 10);

  return null;
end;
$$;

drop trigger if exists offers_notify_price_drop on public.offers;
create trigger offers_notify_price_drop
  after update of price on public.offers
  for each row execute function public.offers_notify_price_drop();

-- ─────────────────────────────────────────────────────────────────────
-- 4. Артикулы: уникальность в пределах одного поставщика
--
--    Одинаковые артикулы у разных поставщиков — норма, это их
--    внутренние коды. А вот два товара с одним артикулом у одного
--    поставщика — почти всегда ошибка повторной загрузки прайса.
--    Индекс не создаётся, если такие дубли уже есть: сначала
--    почистите их, потом выполните этот блок повторно.
-- ─────────────────────────────────────────────────────────────────────
do $$
begin
  create unique index if not exists products_owner_sku_uniq
    on public.products (owner_id, sku)
    where owner_id is not null and sku is not null and sku <> '';
exception when unique_violation then
  raise notice 'Есть товары с одинаковым артикулом у одного поставщика — индекс не создан';
end $$;
