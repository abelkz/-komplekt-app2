-- ============================================================
-- КОМПЛЕКТ · Укрепление — миграция 0006
-- Закрытие RLS-дыр, удаление аккаунта, лимиты Storage,
-- полнотекстовый поиск, настройки/порог уведомлений, очистка.
-- Запускать ПОСЛЕ 0001–0005.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- 1. ВЛАДЕНИЕ: нельзя выставлять предложения от чужой компании
--    и подменять created_by/owner_id.
--    Проверки активны только когда есть auth.uid() (клиент);
--    при SQL-сидинге (auth.uid() = null) — пропускаются.
-- ──────────────────────────────────────────────────────────
create or replace function public.enforce_offer_owner()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    new.owner_id := auth.uid();
    if not exists (
      select 1 from public.suppliers s
      where s.id = new.supplier_id and s.owner_id = auth.uid()
    ) then
      raise exception 'offer.supplier_id не принадлежит текущему пользователю';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_enforce_offer_owner on public.offers;
create trigger trg_enforce_offer_owner
  before insert or update on public.offers
  for each row execute function public.enforce_offer_owner();

create or replace function public.enforce_product_owner()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  return new;
end;
$$;
drop trigger if exists trg_enforce_product_owner on public.products;
create trigger trg_enforce_product_owner
  before insert on public.products
  for each row execute function public.enforce_product_owner();

-- ──────────────────────────────────────────────────────────
-- 2. УДАЛЕНИЕ АККАУНТА (право пользователя / требование сторов и закона РК)
--    Удаляет auth.users → каскадом всё в public.* через FK on delete cascade.
-- ──────────────────────────────────────────────────────────
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Не авторизован';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

-- ──────────────────────────────────────────────────────────
-- 3. ЛИМИТЫ STORAGE для фото товаров (тип и размер ≤ 5 МБ)
-- ──────────────────────────────────────────────────────────
update storage.buckets
   set file_size_limit = 5242880,
       allowed_mime_types = array['image/jpeg','image/png','image/webp']
 where id = 'product-images';

-- ──────────────────────────────────────────────────────────
-- 4. ПОЛНОТЕКСТОВЫЙ ПОИСК (русский) по названию/артикулу/бренду
-- ──────────────────────────────────────────────────────────
alter table public.products
  add column if not exists search_tsv tsvector
  generated always as (
    to_tsvector('russian',
      coalesce(name,'') || ' ' || coalesce(sku,'') || ' ' || coalesce(brand,''))
  ) stored;
create index if not exists products_search_tsv_idx
  on public.products using gin (search_tsv);

-- ──────────────────────────────────────────────────────────
-- 5. НАСТРОЙКИ УВЕДОМЛЕНИЙ + ПОРОГ СНИЖЕНИЯ
-- ──────────────────────────────────────────────────────────
alter table public.users
  add column if not exists notify_price_drops boolean not null default true,
  add column if not exists notify_threshold int not null default 1
    check (notify_threshold between 0 and 90);

alter table public.price_drops
  add column if not exists is_read boolean not null default false;
create index if not exists price_drops_unread_idx
  on public.price_drops (user_id) where is_read = false;

-- Триггер очереди: учитываем настройки и порог пользователя
create or replace function public.on_offer_price_drop()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if NEW.price < OLD.price then
    insert into public.price_drops
      (user_id, product_id, product_name, supplier_name, old_price, new_price)
    select f.user_id, p.id, p.name, s.name, OLD.price, NEW.price
    from public.favorites f
    join public.users u on u.id = f.user_id
    join public.products p on p.id = NEW.product_id
    left join public.suppliers s on s.id = NEW.supplier_id
    where f.product_id = NEW.product_id
      and u.notify_price_drops = true
      and ((OLD.price - NEW.price) / OLD.price * 100) >= u.notify_threshold;
  end if;
  return NEW;
end;
$$;

-- ──────────────────────────────────────────────────────────
-- 6. ОЧИСТКА старых отправленных уведомлений (если доступен pg_cron)
--    Если расширение не включено — этот блок можно пропустить.
-- ──────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule(
      'komplekt-cleanup-price-drops',
      '0 3 * * *',
      $job$ delete from public.price_drops
            where status = 'sent' and created_at < now() - interval '30 days' $job$
    );
  end if;
exception when others then
  raise notice 'pg_cron недоступен — очистку настройте вручную';
end;
$$;
