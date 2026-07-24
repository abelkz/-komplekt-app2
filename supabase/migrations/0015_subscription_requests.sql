-- ============================================================================
-- 0015. Заявки на подписку.
--
-- Приём платежей внутри приложения пока не подключён: эквайринг в
-- Казахстане (Kaspi, CloudPayments, Robokassa) требует договора и
-- проверки бизнеса. До этого момента человек нажимает «Оформить»,
-- заявка попадает сюда, а вы связываетесь и включаете тариф руками.
--
-- Когда появится настоящая оплата, таблица останется полезной: в ней
-- будет история обращений и источник, из которого пришёл платящий.
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- ============================================================================

create table if not exists public.subscription_requests (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  kind        text not null check (kind in ('client', 'supplier')),
  supplier_id bigint references public.suppliers(id) on delete set null,
  contact     text,                       -- телефон или почта для связи
  status      text not null default 'new'
              check (status in ('new', 'contacted', 'paid', 'declined')),
  note        text,
  created_at  timestamptz not null default now()
);

create index if not exists subscription_requests_user_idx
  on public.subscription_requests (user_id, created_at desc);

create index if not exists subscription_requests_new_idx
  on public.subscription_requests (created_at desc)
  where status = 'new';

alter table public.subscription_requests enable row level security;

-- Свои заявки человек видит и создаёт
drop policy if exists subscription_requests_own on public.subscription_requests;
create policy subscription_requests_own on public.subscription_requests
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Администратор видит все — по ним он и продаёт
drop policy if exists subscription_requests_admin on public.subscription_requests;
create policy subscription_requests_admin on public.subscription_requests
  for all to authenticated
  using (exists (select 1 from public.profiles
                  where id = auth.uid() and role = 'admin'));

comment on table public.subscription_requests is
  'Заявки на платный тариф. Пока оплата вне приложения — по ним '
  'администратор связывается и включает тариф вручную';
