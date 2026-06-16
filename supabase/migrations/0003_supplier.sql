-- ============================================================
-- КОМПЛЕКТ · Кабинет поставщика — миграция 0003
-- Статус одобрения, защита роли, события (просмотры/контакты), статистика.
-- Запускать ПОСЛЕ 0001_init.sql.
-- ============================================================

-- ── Статус поставщика: pending → approved / rejected ──
alter table public.users
  add column if not exists status text not null default 'approved'
  check (status in ('pending','approved','rejected'));

-- Обновляем автосоздание профиля: поставщик стартует со статусом pending
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare v_role text;
begin
  v_role := coalesce(new.raw_user_meta_data->>'role', 'buyer');
  insert into public.users (id, full_name, phone, city, role, status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'phone', new.phone),
    coalesce(new.raw_user_meta_data->>'city', 'Астана'),
    v_role,
    case when v_role = 'supplier' then 'pending' else 'approved' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ── Защита роли/статуса от самовольной смены ──
-- Обычный пользователь может стать поставщиком (buyer→supplier, статус pending),
-- но НЕ может сам себя одобрить. Одобрение делает только админ.
create or replace function public.protect_user_role()
returns trigger language plpgsql security definer set search_path = public as $$
declare is_admin boolean;
begin
  select exists(select 1 from public.users u
                where u.id = auth.uid() and u.role = 'admin') into is_admin;
  if is_admin then
    return new;
  end if;
  -- роль: разрешаем только buyer→supplier
  if new.role is distinct from old.role
     and not (old.role = 'buyer' and new.role = 'supplier') then
    new.role := old.role;
  end if;
  -- статус: разрешаем выставлять только 'pending'
  if new.status is distinct from old.status and new.status <> 'pending' then
    new.status := old.status;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_protect_user_role on public.users;
create trigger trg_protect_user_role
  before update on public.users
  for each row execute function public.protect_user_role();

-- ── RPC: стать поставщиком (для текущего пользователя) ──
create or replace function public.become_supplier()
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.users
     set role = 'supplier',
         status = case when status = 'approved' then 'approved' else 'pending' end
   where id = auth.uid();
end;
$$;

-- ============================================================
-- EVENTS — события для статистики поставщика (просмотры/контакты)
-- ============================================================
create table if not exists public.events (
  id          bigint generated always as identity primary key,
  product_id  uuid references public.products(id) on delete cascade,
  supplier_id uuid references public.suppliers(id) on delete cascade,
  user_id     uuid,                 -- кто инициировал (может быть null)
  type        text not null check (type in ('view','contact')),
  created_at  timestamptz not null default now()
);
create index if not exists events_supplier_idx on public.events (supplier_id);
create index if not exists events_product_idx on public.events (product_id);

alter table public.events enable row level security;

-- Поставщик видит только свои события (по своим карточкам компании)
create policy events_owner_read on public.events
  for select using (
    exists (select 1 from public.suppliers s
            where s.id = supplier_id and s.owner_id = auth.uid())
  );

-- ── RPC: лог события (обходит RLS безопасно, пишет от имени системы) ──
create or replace function public.log_event(
  p_product uuid, p_supplier uuid, p_type text
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_supplier is null or p_type not in ('view','contact') then
    return;
  end if;
  insert into public.events (product_id, supplier_id, user_id, type)
  values (p_product, p_supplier, auth.uid(), p_type);
end;
$$;

-- ── RPC: сводная статистика поставщика (просмотры/контакты по товарам) ──
create or replace function public.supplier_stats(p_supplier uuid)
returns table (product_id uuid, views bigint, contacts bigint)
language sql stable as $$
  select e.product_id,
         count(*) filter (where e.type = 'view')    as views,
         count(*) filter (where e.type = 'contact') as contacts
  from public.events e
  where e.supplier_id = p_supplier
  group by e.product_id;
$$;
