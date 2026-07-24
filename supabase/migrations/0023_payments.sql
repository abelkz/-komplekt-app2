-- ============================================================================
-- 0023. Оплата через CloudPayments.
--
-- Таблица платежей + функция выдачи. Платёж создаёт серверная функция
-- (Edge Function create-payment), а подтверждает вебхук CloudPayments
-- (Edge Function cloudpayments-webhook) — он вызывает fulfill_payment,
-- которая включает тариф или начисляет бусты. Обе функции работают под
-- service_role, поэтому fulfill_payment доступна только ему.
-- ============================================================================

create table if not exists public.payments (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  kind        text not null check (kind in ('pro_client','pro_supplier','boost')),
  amount      integer not null check (amount > 0),   -- сумма в тенге
  months      int,                                   -- для подписки
  boost_days  int,                                   -- для буста
  boost_qty   int,
  supplier_id bigint references public.suppliers(id) on delete set null,
  status      text not null default 'new'
              check (status in ('new','paid','failed')),
  provider    text not null default 'cloudpayments',
  invoice_id  text,                                  -- id счёта у провайдера
  created_at  timestamptz not null default now(),
  paid_at     timestamptz
);
create index if not exists payments_user_idx
  on public.payments (user_id, created_at desc);

alter table public.payments enable row level security;

-- Человек видит только свои платежи (для статуса «оплачено» в приложении).
drop policy if exists payments_own on public.payments;
create policy payments_own on public.payments
  for select to authenticated using (auth.uid() = user_id);

-- Пишут только серверные функции (service_role в обход RLS) — напрямую никто.
revoke insert, update, delete on public.payments from authenticated, anon;

-- ── Выдача оплаченного ──────────────────────────────────────────────────────
-- Вызывается вебхуком после подтверждения оплаты. Идемпотентна: повторный
-- вызов по уже оплаченному платежу ничего не делает (CloudPayments может
-- прислать уведомление дважды).
create or replace function public.fulfill_payment(p_payment uuid)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  pay public.payments;
  sup public.suppliers;
  till timestamptz;
  i   int;
  res text;
begin
  select * into pay from public.payments where id = p_payment for update;
  if not found then
    raise exception 'Платёж не найден' using errcode = 'P0002';
  end if;
  if pay.status = 'paid' then
    return 'уже оплачено';
  end if;

  if pay.kind = 'pro_client' then
    update public.profiles
       set plan = 'pro',
           plan_until = greatest(coalesce(plan_until, now()), now())
                        + make_interval(months => coalesce(pay.months, 1))
     where id = pay.user_id;
    res := 'КОМПЛЕКТ Про включён';

  elsif pay.kind = 'pro_supplier' then
    select * into sup from public.suppliers
     where (pay.supplier_id is not null and id = pay.supplier_id)
        or (pay.supplier_id is null and owner_id = pay.user_id)
     order by id limit 1;
    if found then
      till := greatest(coalesce(sup.plan_until, now()), now())
              + make_interval(months => coalesce(pay.months, 1));
      update public.suppliers set plan = 'pro', plan_until = till where id = sup.id;
    end if;
    res := 'Тариф Про поставщика включён';

  elsif pay.kind = 'boost' then
    select * into sup from public.suppliers
     where (pay.supplier_id is not null and id = pay.supplier_id)
        or (pay.supplier_id is null and owner_id = pay.user_id)
     order by id limit 1;
    if found then
      for i in 1..coalesce(pay.boost_qty, 1) loop
        insert into public.boost_credits (supplier_id, days)
        values (sup.id, coalesce(pay.boost_days, 1));
      end loop;
    end if;
    res := 'Бусты начислены';
  end if;

  update public.payments
     set status = 'paid', paid_at = now()
   where id = p_payment;

  return res;
end;
$fn$;

revoke all on function public.fulfill_payment(uuid) from public, authenticated, anon;
grant execute on function public.fulfill_payment(uuid) to service_role;
