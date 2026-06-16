-- ============================================================
-- КОМПЛЕКТ · Схема базы данных (Supabase / PostgreSQL + PostGIS)
-- Миграция 0001 — таблицы, индексы, гео, функции, RLS-политики
-- Выполнять в Supabase: SQL Editor → New query → вставить → Run.
-- ============================================================

-- ── Расширения ──
create extension if not exists postgis;      -- гео-поиск поставщиков рядом
create extension if not exists pg_trgm;      -- быстрый поиск по названию (ILIKE)

-- ============================================================
-- 1. USERS — профили пользователей (ссылаются на auth.users)
--    role: 'buyer' (покупатель) | 'supplier' (продавец) | 'admin'
-- ============================================================
create table if not exists public.users (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text,
  phone       text,
  city        text default 'Астана',
  role        text not null default 'buyer'
              check (role in ('buyer','supplier','admin')),
  avatar_url  text,
  created_at  timestamptz not null default now()
);
comment on table public.users is 'Профили пользователей приложения (ТЗ: users).';

-- Автосоздание профиля при регистрации в Supabase Auth
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.users (id, full_name, phone, city, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'phone', new.phone),
    coalesce(new.raw_user_meta_data->>'city', 'Астана'),
    coalesce(new.raw_user_meta_data->>'role', 'buyer')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- 2. CATEGORIES — категории материалов
--    slug — стабильный ключ (как в прототипе), используется в URL
-- ============================================================
create table if not exists public.categories (
  slug   text primary key,
  name   text not null,
  icon   text,            -- ключ иконки на стороне приложения
  sort   int  not null default 0
);

-- ============================================================
-- 3. SUPPLIERS — поставщики (с гео-точкой PostGIS)
-- ============================================================
create table if not exists public.suppliers (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid references public.users(id) on delete set null,
  name        text not null,
  city        text not null default 'Астана',
  address     text,
  phone       text,
  whatsapp    text,
  website     text,
  description text,
  logo_url    text,
  rating      numeric(2,1) default 0,        -- средний рейтинг 0..5
  lat         double precision,
  lng         double precision,
  -- Гео-точка вычисляется автоматически из lat/lng (для поиска «рядом»)
  geog        geography(Point, 4326)
              generated always as
              (case when lat is not null and lng is not null
                    then ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
                    else null end) stored,
  created_at  timestamptz not null default now()
);
create index if not exists suppliers_geog_idx on public.suppliers using gist (geog);
create index if not exists suppliers_city_idx on public.suppliers (city);

-- ============================================================
-- 4. PRODUCTS — товары каталога
-- ============================================================
create table if not exists public.products (
  id            uuid primary key default gen_random_uuid(),
  category_slug text references public.categories(slug) on delete set null,
  created_by    uuid references public.users(id) on delete set null,
  brand         text,
  name          text not null,
  sku           text,
  unit          text not null default 'шт',     -- м², шт, м, л, кг, упак
  color         text,                            -- hex для заглушки-фона
  description   text,
  rating        numeric(2,1) default 0,
  created_at    timestamptz not null default now()
);
create index if not exists products_category_idx on public.products (category_slug);
-- Триграммный индекс для быстрого поиска по названию и артикулу
create index if not exists products_name_trgm_idx on public.products using gin (name gin_trgm_ops);
create index if not exists products_sku_trgm_idx  on public.products using gin (sku  gin_trgm_ops);

-- ============================================================
-- 5. PRODUCT_IMAGES — галерея фото товара
-- ============================================================
create table if not exists public.product_images (
  id         uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  url        text not null,
  sort       int  not null default 0
);
create index if not exists product_images_product_idx on public.product_images (product_id);

-- ============================================================
-- 6. OFFERS — предложения поставщиков (ядро сравнения цен)
--    Один товар → много предложений от разных поставщиков
-- ============================================================
create table if not exists public.offers (
  id                uuid primary key default gen_random_uuid(),
  product_id        uuid not null references public.products(id) on delete cascade,
  supplier_id       uuid not null references public.suppliers(id) on delete cascade,
  owner_id          uuid references public.users(id) on delete set null,
  price             numeric(12,2) not null check (price > 0),
  currency          text not null default 'KZT',
  in_stock          boolean not null default true,
  price_updated_at  timestamptz not null default now(),
  unique (product_id, supplier_id)
);
create index if not exists offers_product_idx  on public.offers (product_id);
create index if not exists offers_supplier_idx on public.offers (supplier_id);

-- ============================================================
-- 7. REVIEWS — отзывы на товары
-- ============================================================
create table if not exists public.reviews (
  id         uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  user_id    uuid not null references public.users(id) on delete cascade,
  rating     int  not null check (rating between 1 and 5),
  text       text,
  created_at timestamptz not null default now(),
  unique (product_id, user_id)
);
create index if not exists reviews_product_idx on public.reviews (product_id);

-- ============================================================
-- 8. FAVORITES — избранное пользователя
-- ============================================================
create table if not exists public.favorites (
  user_id    uuid not null references public.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

-- ============================================================
-- 9. COLLECTIONS — подборки/проекты пользователя
-- ============================================================
create table if not exists public.collections (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users(id) on delete cascade,
  name       text not null default 'Мой проект',
  created_at timestamptz not null default now()
);
create index if not exists collections_user_idx on public.collections (user_id);

-- ============================================================
-- 10. COLLECTION_ITEMS — позиции внутри подборки (с количеством)
-- ============================================================
create table if not exists public.collection_items (
  id            uuid primary key default gen_random_uuid(),
  collection_id uuid not null references public.collections(id) on delete cascade,
  product_id    uuid not null references public.products(id) on delete cascade,
  qty           numeric(12,2) not null default 1 check (qty > 0),
  created_at    timestamptz not null default now(),
  unique (collection_id, product_id)
);
create index if not exists collection_items_collection_idx on public.collection_items (collection_id);

-- ============================================================
-- ФУНКЦИЯ: поставщики рядом (гео-поиск, сорт. по расстоянию)
--   p_lat, p_lng — точка пользователя; p_radius_m — радиус, м.
-- ============================================================
create or replace function public.nearby_suppliers(
  p_lat double precision,
  p_lng double precision,
  p_radius_m double precision default 30000
)
returns table (
  id uuid, name text, city text, address text,
  phone text, whatsapp text, website text, logo_url text,
  rating numeric, lat double precision, lng double precision,
  distance_m double precision
)
language sql stable
as $$
  select s.id, s.name, s.city, s.address,
         s.phone, s.whatsapp, s.website, s.logo_url,
         s.rating, s.lat, s.lng,
         ST_Distance(s.geog, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography) as distance_m
  from public.suppliers s
  where s.geog is not null
    and ST_DWithin(s.geog, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography, p_radius_m)
  order by distance_m asc;
$$;

-- ============================================================
-- ФУНКЦИЯ: пересчёт рейтинга товара по отзывам (триггер)
-- ============================================================
create or replace function public.recalc_product_rating()
returns trigger language plpgsql as $$
declare pid uuid;
begin
  pid := coalesce(new.product_id, old.product_id);
  update public.products p
     set rating = coalesce((select round(avg(r.rating)::numeric, 1)
                            from public.reviews r where r.product_id = pid), 0)
   where p.id = pid;
  return null;
end;
$$;
drop trigger if exists trg_recalc_rating on public.reviews;
create trigger trg_recalc_rating
  after insert or update or delete on public.reviews
  for each row execute function public.recalc_product_rating();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table public.users            enable row level security;
alter table public.categories       enable row level security;
alter table public.suppliers        enable row level security;
alter table public.products         enable row level security;
alter table public.product_images   enable row level security;
alter table public.offers           enable row level security;
alter table public.reviews          enable row level security;
alter table public.favorites        enable row level security;
alter table public.collections      enable row level security;
alter table public.collection_items enable row level security;

-- ── USERS: каждый видит/правит только свой профиль ──
create policy users_select_own on public.users
  for select using (auth.uid() = id);
create policy users_update_own on public.users
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- ── CATEGORIES: чтение всем, запись — только админ ──
create policy categories_read on public.categories
  for select using (true);
create policy categories_admin_write on public.categories
  for all using (exists (select 1 from public.users u
                         where u.id = auth.uid() and u.role = 'admin'))
  with check (exists (select 1 from public.users u
                      where u.id = auth.uid() and u.role = 'admin'));

-- ── SUPPLIERS: читают все; правит владелец ──
create policy suppliers_read on public.suppliers
  for select using (true);
create policy suppliers_owner_write on public.suppliers
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- ── PRODUCTS: читают все; правит автор ──
create policy products_read on public.products
  for select using (true);
create policy products_owner_write on public.products
  for all using (auth.uid() = created_by) with check (auth.uid() = created_by);

-- ── PRODUCT_IMAGES: читают все; правит автор товара ──
create policy product_images_read on public.product_images
  for select using (true);
create policy product_images_owner_write on public.product_images
  for all using (exists (select 1 from public.products p
                         where p.id = product_id and p.created_by = auth.uid()))
  with check (exists (select 1 from public.products p
                      where p.id = product_id and p.created_by = auth.uid()));

-- ── OFFERS: читают все; правит владелец предложения ──
create policy offers_read on public.offers
  for select using (true);
create policy offers_owner_write on public.offers
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- ── REVIEWS: читают все; пишет/правит автор ──
create policy reviews_read on public.reviews
  for select using (true);
create policy reviews_author_write on public.reviews
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── FAVORITES: только свои ──
create policy favorites_own on public.favorites
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── COLLECTIONS: только свои ──
create policy collections_own on public.collections
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── COLLECTION_ITEMS: только в своих подборках ──
create policy collection_items_own on public.collection_items
  for all using (exists (select 1 from public.collections c
                         where c.id = collection_id and c.user_id = auth.uid()))
  with check (exists (select 1 from public.collections c
                      where c.id = collection_id and c.user_id = auth.uid()));
