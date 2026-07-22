-- ============================================================================
-- 0010. Кабинет поставщика: заявка и статистика.
--
-- Приложение вызывает две функции, которых в живой базе нет:
--   become_supplier — оформить заявку на статус поставщика;
--   supplier_stats  — просмотры и обращения по товарам поставщика.
--
-- Обе SECURITY DEFINER: пользователь не может сам себе поставить
-- status='approved' — только 'pending'. Одобряет администратор
-- в панели admin.html, меняя profiles.status.
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────
-- 1. Заявка на статус поставщика
--
--    Пользователь заполняет компанию, город и телефон — профиль
--    переводится в role='supplier', status='pending'. Уже одобренного
--    поставщика функция не трогает (иначе кабинет закрылся бы).
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.become_supplier(
  p_company text,
  p_city    text default null,
  p_phone   text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  me  uuid := auth.uid();
  row public.profiles;
begin
  if me is null then
    raise exception 'Нужно войти в аккаунт' using errcode = '28000';
  end if;
  if coalesce(btrim(p_company), '') = '' then
    raise exception 'Укажите название компании' using errcode = '22023';
  end if;

  update public.profiles p
     set company = btrim(p_company),
         city    = coalesce(nullif(btrim(p_city), ''), p.city),
         phone   = coalesce(nullif(btrim(p_phone), ''), p.phone),
         role    = case when p.role = 'admin' then p.role else 'supplier' end,
         -- одобренного не понижаем; всем остальным — на проверку
         status  = case when p.status = 'approved' then p.status else 'pending' end
   where p.id = me
  returning p.* into row;

  if not found then
    raise exception 'Профиль не найден' using errcode = 'P0002';
  end if;

  return row;
end;
$$;

revoke all on function public.become_supplier(text, text, text) from public;
grant execute on function public.become_supplier(text, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Статистика по товарам поставщика
--
--    Считает события просмотра карточки и обращения к поставщику.
--    Отдаёт данные только владельцу компании.
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.supplier_stats(p_supplier bigint)
returns table (product_id bigint, views bigint, contacts bigint)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.suppliers s
     where s.id = p_supplier and s.owner_id = auth.uid()
  ) then
    raise exception 'Это не ваша компания' using errcode = '42501';
  end if;

  return query
    select e.product_id,
           count(*) filter (where e.type in ('view', 'product_view'))          as views,
           count(*) filter (where e.type in ('contact', 'call', 'whatsapp'))   as contacts
      from public.events e
     where e.product_id is not null
       and (e.supplier_id = p_supplier
            or e.product_id in (select o.product_id
                                  from public.offers o
                                 where o.supplier_id = p_supplier))
     group by e.product_id;
end;
$$;

revoke all on function public.supplier_stats(bigint) from public;
grant execute on function public.supplier_stats(bigint) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Индексы под запросы кабинета
-- ─────────────────────────────────────────────────────────────────────
create index if not exists products_owner_idx on public.products (owner_id);
create index if not exists offers_owner_idx   on public.offers   (owner_id);
create index if not exists events_product_idx on public.events   (product_id);
