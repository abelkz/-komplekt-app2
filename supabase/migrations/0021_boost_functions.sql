-- ============================================================================
-- 0021. Функции продвижения: подъём, покупка Буста, выдача админом.
-- Идёт после 0020 (таблицы). Заменяет старый promote_offer.
-- ============================================================================

-- Сводка для кабинета: моя компания, остаток бесплатных подъёмов Pro,
-- купленные кредиты по срокам.
create or replace function public.my_boost_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  sup     public.suppliers;
  used    int;
  is_pro  boolean;
  credits jsonb;
begin
  select * into sup from public.suppliers where owner_id = auth.uid() order by id limit 1;
  if not found then
    return jsonb_build_object('free_left', 0, 'is_pro', false, 'credits', '[]'::jsonb);
  end if;

  is_pro := public.supplier_plan_active(sup.plan, sup.plan_until);

  select count(*) into used
    from public.promotions
   where supplier_id = sup.id
     and source = 'pro_free'
     and created_at >= date_trunc('month', now());

  select coalesce(jsonb_agg(jsonb_build_object('days', days, 'count', c)), '[]'::jsonb)
    into credits
    from (select days, count(*) c
            from public.boost_credits
           where supplier_id = sup.id and status = 'available'
           group by days order by days) t;

  return jsonb_build_object(
    'is_pro', is_pro,
    'free_left', case when is_pro
                      then greatest(0, public.pro_free_boosts_per_month() - used)
                      else 0 end,
    'credits', credits
  );
end;
$fn$;

-- Поднять товар в топ. Сначала пробуем бесплатную норму Pro (1 или 3 дня),
-- иначе списываем купленный кредит ровно на нужный срок.
create or replace function public.promote_offer(p_offer bigint, p_days int default 3)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $fn$
declare
  o       public.offers;
  sup     public.suppliers;
  used    int;
  credit  public.boost_credits;
  until   timestamptz;
  src     text;
begin
  if p_days not in (1, 3, 7) then
    raise exception 'Срок подъёма — 1, 3 или 7 дней' using errcode = '22023';
  end if;

  select * into o from public.offers where id = p_offer;
  if not found then
    raise exception 'Предложение не найдено' using errcode = 'P0002';
  end if;
  if o.owner_id is distinct from auth.uid() then
    raise exception 'Это не ваше предложение' using errcode = '42501';
  end if;

  select * into sup from public.suppliers where id = o.supplier_id;

  -- 1) бесплатная норма Pro: только 1 или 3 дня и не больше нормы в месяц
  if p_days in (1, 3) and public.supplier_plan_active(sup.plan, sup.plan_until) then
    select count(*) into used
      from public.promotions
     where supplier_id = sup.id and source = 'pro_free'
       and created_at >= date_trunc('month', now());
    if used < public.pro_free_boosts_per_month() then
      src := 'pro_free';
    end if;
  end if;

  -- 2) иначе — купленный кредит ровно на этот срок
  if src is null then
    select * into credit
      from public.boost_credits
     where supplier_id = sup.id and status = 'available' and days = p_days
     order by created_at limit 1
     for update skip locked;
    if not found then
      raise exception 'Нет доступных подъёмов на % дн. Купите Буст.', p_days
        using errcode = 'P0002';
    end if;
    update public.boost_credits set status = 'used', used_at = now()
     where id = credit.id;
    src := 'boost';
  end if;

  until := now() + make_interval(days => p_days);
  update public.offers set promoted_until = until where id = p_offer;
  insert into public.promotions (offer_id, supplier_id, days, source, until)
  values (p_offer, sup.id, p_days, src, until);

  return until;
end;
$fn$;

-- Заявка на покупку Буста от поставщика.
create or replace function public.order_boost(p_days int, p_qty int default 1)
returns bigint
language plpgsql
security definer
set search_path = public
as $fn$
declare
  sup public.suppliers;
  oid bigint;
begin
  if p_days not in (1, 3, 7) then
    raise exception 'Срок — 1, 3 или 7 дней' using errcode = '22023';
  end if;
  if p_qty < 1 or p_qty > 50 then
    raise exception 'Количество — от 1 до 50' using errcode = '22023';
  end if;

  select * into sup from public.suppliers where owner_id = auth.uid() order by id limit 1;
  if not found then
    raise exception 'Сначала заведите компанию' using errcode = 'P0002';
  end if;

  insert into public.boost_orders (supplier_id, user_id, days, qty)
  values (sup.id, auth.uid(), p_days, p_qty)
  returning id into oid;
  return oid;
end;
$fn$;

-- Админ подтверждает оплату: начисляет кредиты и закрывает заявку.
create or replace function public.admin_grant_boost(p_order bigint)
returns int
language plpgsql
security definer
set search_path = public
as $fn$
declare
  ord public.boost_orders;
  i   int;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Нужны права администратора' using errcode = '42501';
  end if;
  select * into ord from public.boost_orders where id = p_order;
  if not found then
    raise exception 'Заявка не найдена' using errcode = 'P0002';
  end if;
  if ord.status = 'paid' then
    raise exception 'Заявка уже оплачена' using errcode = '22023';
  end if;

  for i in 1..ord.qty loop
    insert into public.boost_credits (supplier_id, days) values (ord.supplier_id, ord.days);
  end loop;

  update public.boost_orders set status = 'paid' where id = p_order;
  return ord.qty;
end;
$fn$;

revoke all on function public.promote_offer(bigint, int)     from public;
revoke all on function public.order_boost(int, int)          from public;
revoke all on function public.admin_grant_boost(bigint)      from public;
revoke all on function public.my_boost_status()              from public;
grant execute on function public.promote_offer(bigint, int)  to authenticated;
grant execute on function public.order_boost(int, int)       to authenticated;
grant execute on function public.admin_grant_boost(bigint)   to authenticated;
grant execute on function public.my_boost_status()           to authenticated;
