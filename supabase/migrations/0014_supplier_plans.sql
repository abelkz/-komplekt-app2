-- ============================================================================
-- 0014. Платные возможности поставщиков: тариф, проверка, продвижение.
--
-- ЗАМЫСЕЛ:
--   plan            — тариф компании: free или pro;
--   verified        — «проверенный поставщик». Ставится администратором
--                     ПОСЛЕ проверки документов, а не автоматически за
--                     оплату: значок утверждает факт проверки, и торговать
--                     им — вводить покупателя в заблуждение;
--   promoted_until  — до какого момента товар показывается в топе списков.
--
-- ЧЕГО ЗДЕСЬ НАМЕРЕННО НЕТ:
--   Продвижение НЕ меняет порядок в шкале цен внутри карточки товара.
--   Там всегда первым идёт самый дешёвый — это обещание, ради которого
--   приложением пользуются. Продвижение работает только в списках
--   и в поиске, и товар в них помечается как продвигаемый.
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────
-- 1. Тариф и проверка у компании
-- ─────────────────────────────────────────────────────────────────────
alter table public.suppliers
  add column if not exists plan text not null default 'free',
  add column if not exists plan_until timestamptz,
  add column if not exists verified boolean not null default false,
  add column if not exists verified_at timestamptz;

do $do$
begin
  alter table public.suppliers
    add constraint suppliers_plan_check check (plan in ('free', 'pro'));
exception when duplicate_object then
  null;
end $do$;

comment on column public.suppliers.plan is
  'free | pro — тариф компании';
comment on column public.suppliers.plan_until is
  'До какого момента действует оплаченный тариф; null — бессрочно (для free)';
comment on column public.suppliers.verified is
  'Проверенный поставщик. Ставится администратором после проверки документов';

-- ─────────────────────────────────────────────────────────────────────
-- 2. Продвижение товара
-- ─────────────────────────────────────────────────────────────────────
alter table public.offers
  add column if not exists promoted_until timestamptz;

comment on column public.offers.promoted_until is
  'До какого момента предложение показывается в топе списков '
  '(в шкале цен внутри товара порядок не меняется — там только цена)';

create index if not exists offers_promoted_idx
  on public.offers (promoted_until)
  where promoted_until is not null;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Тариф действует, только если оплачен срок
--
--    Отдельная функция, чтобы не проверять срок в каждом запросе
--    и не забыть про истёкшую оплату.
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.supplier_plan_active(p_plan text, p_until timestamptz)
returns boolean
language sql
stable                       -- зависит от now(); immutable кэшировал бы результат
as $fn$
  select p_plan = 'pro' and (p_until is null or p_until > now());
$fn$;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Управление тарифом и проверкой — только администратор
--
--    Поставщик не может сам поставить себе pro или значок проверки.
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.admin_set_supplier_plan(
  p_supplier bigint,
  p_plan text,
  p_until timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if not exists (select 1 from public.profiles
                  where id = auth.uid() and role = 'admin') then
    raise exception 'Только администратор' using errcode = '42501';
  end if;
  if p_plan not in ('free', 'pro') then
    raise exception 'Тариф может быть free или pro' using errcode = '22023';
  end if;
  update public.suppliers
     set plan = p_plan,
         plan_until = case when p_plan = 'pro' then p_until else null end
   where id = p_supplier;
end;
$fn$;

create or replace function public.admin_set_supplier_verified(
  p_supplier bigint,
  p_verified boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if not exists (select 1 from public.profiles
                  where id = auth.uid() and role = 'admin') then
    raise exception 'Только администратор' using errcode = '42501';
  end if;
  update public.suppliers
     set verified = p_verified,
         verified_at = case when p_verified then now() else null end
   where id = p_supplier;
end;
$fn$;

revoke all on function public.admin_set_supplier_plan(bigint, text, timestamptz) from public;
revoke all on function public.admin_set_supplier_verified(bigint, boolean) from public;
grant execute on function public.admin_set_supplier_plan(bigint, text, timestamptz) to authenticated;
grant execute on function public.admin_set_supplier_verified(bigint, boolean) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 5. Продвинуть свой товар — только поставщику с тарифом pro
--
--    Списание денег происходит вне базы: пока продажи ручные,
--    администратор включает тариф после оплаты.
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.promote_offer(p_offer bigint, p_days int default 7)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $fn$
declare
  s record;
  until timestamptz;
begin
  select o.id, o.owner_id, sup.plan, sup.plan_until
    into s
    from public.offers o
    join public.suppliers sup on sup.id = o.supplier_id
   where o.id = p_offer;

  if not found then
    raise exception 'Предложение не найдено' using errcode = 'P0002';
  end if;
  if s.owner_id is distinct from auth.uid() then
    raise exception 'Это не ваше предложение' using errcode = '42501';
  end if;
  if not public.supplier_plan_active(s.plan, s.plan_until) then
    raise exception 'Продвижение доступно на тарифе Pro' using errcode = '42501';
  end if;
  if p_days < 1 or p_days > 90 then
    raise exception 'Срок продвижения — от 1 до 90 дней' using errcode = '22023';
  end if;

  until := now() + make_interval(days => p_days);
  update public.offers set promoted_until = until where id = p_offer;
  return until;
end;
$fn$;

grant execute on function public.promote_offer(bigint, int) to authenticated;
