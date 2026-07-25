-- ============================================================================
-- 0017. Тариф у клиента и включение тарифа прямо из заявки.
--
-- До этого «Оплачено» в панели только меняло статус заявки: у поставщика
-- тариф надо было включать отдельной функцией, а у дизайнера хранить его
-- было негде вовсе. Теперь одна кнопка включает тариф тому, кто просил.
-- ============================================================================

alter table public.profiles
  add column if not exists plan       text not null default 'free',
  add column if not exists plan_until timestamptz;

do $do$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_plan_check') then
    alter table public.profiles
      add constraint profiles_plan_check check (plan in ('free', 'pro'));
  end if;
end
$do$;

comment on column public.profiles.plan is
  'Тариф пользователя: free или pro. У поставщика тариф компании лежит '
  'отдельно, в suppliers.plan — он про продвижение и значок проверки';

-- Активен ли тариф прямо сейчас. Пустой plan_until — бессрочно.
create or replace function public.plan_active(p_plan text, p_until timestamptz)
returns boolean
language sql
stable                       -- зависит от now(); immutable кэшировал бы результат
as $fn$
  select p_plan = 'pro' and (p_until is null or p_until > now());
$fn$;

-- ── Включение тарифа по заявке ──────────────────────────────────────────────
create or replace function public.admin_activate_request(
  p_request bigint,
  p_months  int default 1
)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  r        public.subscription_requests;
  sup      public.suppliers;
  new_till timestamptz;
  result   text;
begin
  if not exists (select 1 from public.profiles
                  where id = auth.uid() and role = 'admin') then
    raise exception 'Нужны права администратора' using errcode = '42501';
  end if;
  if coalesce(p_months, 0) < 1 then
    raise exception 'Срок должен быть не меньше месяца' using errcode = '22023';
  end if;

  select * into r from public.subscription_requests where id = p_request;
  if not found then
    raise exception 'Заявка не найдена' using errcode = 'P0002';
  end if;

  if r.kind = 'supplier' then
    -- компания из заявки, а если её там нет — компания этого владельца
    select * into sup from public.suppliers
     where (r.supplier_id is not null and id = r.supplier_id)
        or (r.supplier_id is null and owner_id = r.user_id)
     order by id limit 1;

    if not found then
      raise exception 'У этого пользователя нет компании — сначала одобрите его как поставщика'
        using errcode = 'P0002';
    end if;

    -- продлеваем от текущей даты окончания, а не с нуля
    new_till := greatest(coalesce(sup.plan_until, now()), now())
                + make_interval(months => p_months);
    update public.suppliers
       set plan = 'pro', plan_until = new_till
     where id = sup.id;
    result := 'Тариф Про для «' || coalesce(sup.name, 'компании')
              || '» до ' || to_char(new_till, 'DD.MM.YYYY');
  else
    select greatest(coalesce(plan_until, now()), now())
             + make_interval(months => p_months)
      into new_till
      from public.profiles where id = r.user_id;

    if new_till is null then
      raise exception 'Профиль не найден' using errcode = 'P0002';
    end if;

    update public.profiles
       set plan = 'pro', plan_until = new_till
     where id = r.user_id;
    result := 'КОМПЛЕКТ Про до ' || to_char(new_till, 'DD.MM.YYYY');
  end if;

  update public.subscription_requests
     set status = 'paid',
         note   = coalesce(note || ' / ', '') || result
   where id = p_request;

  return result;
end;
$fn$;

revoke all on function public.admin_activate_request(bigint, int) from public;
grant execute on function public.admin_activate_request(bigint, int) to authenticated;
