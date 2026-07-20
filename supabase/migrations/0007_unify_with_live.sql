-- ============================================================================
-- 0007. Сведение Flutter-приложения и веб-версии на ОДНУ базу.
--
-- Живая база (её использует Telegram mini-app) уже содержит:
--   categories, brands, products, offers, suppliers, profiles,
--   favorites, projects, project_items, events
-- Ключи там ЦЕЛОЧИСЛЕННЫЕ (products.id = 2, 3, …), а не uuid.
--
-- Эта миграция ТОЛЬКО ДОБАВЛЯЕТ недостающее. Она не переименовывает
-- и не удаляет ни одной существующей таблицы или колонки, поэтому
-- работающая веб-версия продолжает работать без изменений.
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- Перед запуском сделайте бэкап (Database → Backups).
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────
-- 1. Отзывы о товаре
-- ─────────────────────────────────────────────────────────────────────
create table if not exists public.reviews (
  id         uuid primary key default gen_random_uuid(),
  product_id bigint not null references public.products(id) on delete cascade,
  user_id    uuid   not null references auth.users(id) on delete cascade,
  rating     int    not null check (rating between 1 and 5),
  text       text,
  created_at timestamptz not null default now(),
  unique (product_id, user_id)
);

create index if not exists reviews_product_idx on public.reviews (product_id);

alter table public.reviews enable row level security;

drop policy if exists reviews_read on public.reviews;
create policy reviews_read on public.reviews
  for select using (true);

drop policy if exists reviews_write_own on public.reviews;
create policy reviews_write_own on public.reviews
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 2. Дополнительные фото товара
--    (основное фото остаётся в products.image_url — его читает веб)
-- ─────────────────────────────────────────────────────────────────────
create table if not exists public.product_images (
  id         uuid primary key default gen_random_uuid(),
  product_id bigint not null references public.products(id) on delete cascade,
  url        text not null,
  sort       int  not null default 0
);

create index if not exists product_images_product_idx
  on public.product_images (product_id, sort);

alter table public.product_images enable row level security;

drop policy if exists product_images_read on public.product_images;
create policy product_images_read on public.product_images
  for select using (true);

-- писать фото может только владелец товара
drop policy if exists product_images_write_owner on public.product_images;
create policy product_images_write_owner on public.product_images
  for all to authenticated
  using (exists (select 1 from public.products p
                 where p.id = product_id and p.owner_id = auth.uid()))
  with check (exists (select 1 from public.products p
                      where p.id = product_id and p.owner_id = auth.uid()));

-- ─────────────────────────────────────────────────────────────────────
-- 3. Очередь уведомлений о снижении цены
-- ─────────────────────────────────────────────────────────────────────
create table if not exists public.price_drops (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  product_id    bigint references public.products(id) on delete cascade,
  product_name  text,
  supplier_name text,
  old_price     numeric(12,2),
  new_price     numeric(12,2),
  status        text not null default 'pending'
                check (status in ('pending','sent','error')),
  created_at    timestamptz not null default now(),
  sent_at       timestamptz
);

create index if not exists price_drops_user_idx
  on public.price_drops (user_id, created_at desc);

alter table public.price_drops enable row level security;

-- пользователь видит только свои уведомления; создаёт их серверная функция
drop policy if exists price_drops_read_own on public.price_drops;
create policy price_drops_read_own on public.price_drops
  for select to authenticated using (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 4. Токены устройств для пуш-уведомлений (FCM)
-- ─────────────────────────────────────────────────────────────────────
create table if not exists public.device_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  platform   text,                       -- ios | android
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_user_idx
  on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

drop policy if exists device_tokens_own on public.device_tokens;
create policy device_tokens_own on public.device_tokens
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 5. Единый идентификатор пользователя
--
--    Сейчас веб опознаёт человека по user_tg_id (число из Telegram),
--    а Flutter — по сессии Supabase (uuid). Чтобы избранное и комплекты
--    были общими, добавляем uuid-колонку РЯДОМ со старой.
--    Старая колонка остаётся и продолжает работать — веб не ломается.
-- ─────────────────────────────────────────────────────────────────────
alter table public.favorites add column if not exists user_id uuid
  references auth.users(id) on delete cascade;

alter table public.projects  add column if not exists user_id uuid
  references auth.users(id) on delete cascade;

create index if not exists favorites_user_id_idx on public.favorites (user_id);
create index if not exists projects_user_id_idx  on public.projects  (user_id);

-- user_tg_id больше не обязателен: у пользователей, вошедших по
-- телефону или Google, его нет.
alter table public.favorites alter column user_tg_id drop not null;
alter table public.projects  alter column user_tg_id drop not null;

-- ─────────────────────────────────────────────────────────────────────
-- 6. Колонки, которых ждёт Flutter, но нет в живой базе
--    Все со значениями по умолчанию — существующие строки не страдают,
--    веб-версия этих колонок просто не запрашивает.
-- ─────────────────────────────────────────────────────────────────────
alter table public.products  add column if not exists description text;
alter table public.products  add column if not exists rating numeric(3,2) not null default 0;
alter table public.suppliers add column if not exists whatsapp text;

-- ─────────────────────────────────────────────────────────────────────
-- 7. Средний рейтинг товара пересчитывается из отзывов
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.recalc_product_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pid bigint := coalesce(new.product_id, old.product_id);
begin
  update public.products p
     set rating = coalesce((select round(avg(r.rating)::numeric, 2)
                              from public.reviews r
                             where r.product_id = pid), 0)
   where p.id = pid;
  return null;
end;
$$;

drop trigger if exists reviews_recalc_rating on public.reviews;
create trigger reviews_recalc_rating
  after insert or update or delete on public.reviews
  for each row execute function public.recalc_product_rating();
