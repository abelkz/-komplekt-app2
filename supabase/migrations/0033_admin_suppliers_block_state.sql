-- ============================================================================
-- 0033. Состояние блокировки в списке поставщиков админки.
--
-- admin_suppliers (0030) отдаёт показатели компании, но ничего не знает о
-- блокировке из 0032. Без этих двух полей админка не может показать, кто
-- заблокирован, и кнопка «Разблокировать» появиться не из чего.
--
-- Функцию именно DROP + CREATE, а не CREATE OR REPLACE: меняется набор
-- колонок в returns table, а его replace менять не умеет — упадёт с
-- «cannot change return type of existing function».
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

drop function if exists public.admin_suppliers(int);

create function public.admin_suppliers(p_days int default 30)
returns table (
  supplier_id   bigint,
  name          text,
  city          text,
  plan          text,
  plan_until    timestamptz,
  verified      boolean,
  status        text,
  products      bigint,
  offers        bigint,
  views         bigint,
  contacts      bigint,
  last_price_at timestamptz,
  blocked_until timestamptz,
  block_reason  text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  since timestamptz := now() - make_interval(days => greatest(p_days, 1));
begin
  perform public.admin_guard();

  return query
  select
    s.id,
    s.name,
    s.city,
    s.plan,
    s.plan_until,
    coalesce(s.verified, false),
    s.status,
    (select count(distinct o.product_id) from public.offers o
      where o.supplier_id = s.id),
    (select count(*) from public.offers o where o.supplier_id = s.id),
    (select count(*) from public.events v
      where v.supplier_id = s.id and v.type = 'view' and v.created_at >= since),
    (select count(*) from public.events v
      where v.supplier_id = s.id and v.type = 'contact' and v.created_at >= since),
    (select max(o.price_updated_at) from public.offers o
      where o.supplier_id = s.id),
    s.blocked_until,
    s.block_reason
  from public.suppliers s
  -- Заблокированные — наверх: с ними и нужно что-то решать. Дальше по
  -- обращениям: просмотр можно накрутить, звонок — это уже сделка.
  order by (s.blocked_until is not null and s.blocked_until > now()) desc,
           11 desc, 10 desc, s.name;
end;
$$;

revoke all on function public.admin_suppliers(int) from anon;
grant execute on function public.admin_suppliers(int) to authenticated;
