-- ============================================================
-- КОМПЛЕКТ · Пуш-уведомления о снижении цены — миграция 0005
-- Токены устройств, очередь уведомлений, триггер на падение цены.
-- Запускать ПОСЛЕ 0001_init.sql.
-- ============================================================

-- ── Токены устройств (FCM) для отправки пушей ──
create table if not exists public.device_tokens (
  token      text primary key,
  user_id    uuid not null references public.users(id) on delete cascade,
  platform   text,                       -- ios | android
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Пользователь управляет только своими токенами
create policy device_tokens_own on public.device_tokens
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ============================================================
-- Очередь уведомлений о снижении цены (outbox).
-- Триггер кладёт сюда строки, Edge Function их рассылает.
-- ============================================================
create table if not exists public.price_drops (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references public.users(id) on delete cascade,
  product_id    uuid references public.products(id) on delete cascade,
  product_name  text,
  supplier_name text,
  old_price     numeric(12,2),
  new_price     numeric(12,2),
  status        text not null default 'pending'
                check (status in ('pending','sent','error')),
  created_at    timestamptz not null default now(),
  sent_at       timestamptz
);
create index if not exists price_drops_status_idx on public.price_drops (status);

alter table public.price_drops enable row level security;

-- Пользователь видит свою историю снижений (для экрана уведомлений в будущем)
create policy price_drops_own_read on public.price_drops
  for select using (auth.uid() = user_id);

-- ============================================================
-- Триггер: при снижении цены предложения — поставить в очередь
-- уведомления всем, у кого этот товар в избранном.
-- ============================================================
create or replace function public.on_offer_price_drop()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if NEW.price < OLD.price then
    insert into public.price_drops
      (user_id, product_id, product_name, supplier_name, old_price, new_price)
    select f.user_id, p.id, p.name, s.name, OLD.price, NEW.price
    from public.favorites f
    join public.products p on p.id = NEW.product_id
    left join public.suppliers s on s.id = NEW.supplier_id
    where f.product_id = NEW.product_id;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_offer_price_drop on public.offers;
create trigger trg_offer_price_drop
  after update of price on public.offers
  for each row execute function public.on_offer_price_drop();

-- ============================================================
-- ДАЛЕЕ (в Dashboard, см. README):
--   1) Database Webhook: на INSERT в public.price_drops → вызывает
--      Edge Function "send-price-alerts" (она шлёт пуш в FCM).
--   2) Секреты функции: FCM_PROJECT_ID, FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY.
-- ============================================================
