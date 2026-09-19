-- ============================================================
-- КОМПЛЕКТ · 0035 — управление марками из админки
--
-- Зачем. Марку заводит любой поставщик, просто вписав её в форму товара
-- (RPC set_product_brand, миграция 0034). Нормализация там ловит только
-- регистр и пробелы: «kerama marazzi» подтянется к «Kerama Marazzi».
-- Но кириллическую «Керама Марацци» от латинской «Kerama Marazzi» она
-- не отличит, а латинскую C от кириллической С в «Cersanit» не отличит
-- и человек. Такие пары надо склеивать руками, а склеивать было негде.
--
-- Проверка администратора везде пишется через public.profiles: таблицы
-- public.users в живой базе НЕТ, она есть только в схеме 0001_init.sql
-- (см. CLAUDE.md §6.1).
-- ============================================================

-- Имена возвращаемых колонок нарочно не совпадают с именами колонок
-- таблиц (brand_id, а не id): в plpgsql OUT-параметры видны внутри
-- запроса и дают «column reference is ambiguous».
create or replace function public.admin_brands()
returns table (brand_id bigint, brand_name text, products_count bigint)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin') then
    raise exception 'Только для администратора' using errcode = '42501';
  end if;

  return query
    select b.id, b.name, count(pr.id)
    from public.brands b
    left join public.products pr on pr.brand_id = b.id
    group by b.id, b.name
    -- Пустые марки наверх: с ними и надо что-то делать
    order by count(pr.id), b.name;
end;
$$;

-- Переименовать марку.
create or replace function public.admin_rename_brand(
  p_brand bigint,
  p_name  text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare n text := nullif(btrim(coalesce(p_name, '')), '');
begin
  if not exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin') then
    raise exception 'Только для администратора' using errcode = '42501';
  end if;

  if n is null then
    raise exception 'Название марки не может быть пустым' using errcode = '22023';
  end if;

  -- Своё же название в другом регистре — это просто правка написания,
  -- её пропускаем. А вот совпадение с ЧУЖОЙ маркой — это склейка,
  -- и делать её надо осознанно: товары той марки никуда не денутся.
  if exists (
    select 1 from public.brands b
    where b.id <> p_brand and lower(btrim(b.name)) = lower(n)
  ) then
    raise exception 'Марка «%» уже есть — воспользуйтесь объединением', n
      using errcode = '23505';
  end if;

  update public.brands set name = n where id = p_brand;

  if not found then
    raise exception 'Марка не найдена' using errcode = 'P0002';
  end if;
end;
$$;

-- Склеить две марки: товары переезжают в p_into, p_from удаляется.
-- Возвращает, сколько товаров переехало.
create or replace function public.admin_merge_brands(
  p_from bigint,
  p_into bigint
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare moved integer;
begin
  if not exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin') then
    raise exception 'Только для администратора' using errcode = '42501';
  end if;

  if p_from = p_into then
    raise exception 'Нельзя объединить марку саму с собой' using errcode = '22023';
  end if;

  if not exists (select 1 from public.brands where id = p_from)
     or not exists (select 1 from public.brands where id = p_into) then
    raise exception 'Марка не найдена' using errcode = 'P0002';
  end if;

  update public.products set brand_id = p_into where brand_id = p_from;
  get diagnostics moved = row_count;

  delete from public.brands where id = p_from;

  return moved;
end;
$$;

-- Удалить марку. Только пустую: у товаров brand_id обнулять молча нельзя,
-- иначе марка исчезнет из карточек без следа и без предупреждения.
create or replace function public.admin_delete_brand(p_brand bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare used integer;
begin
  if not exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin') then
    raise exception 'Только для администратора' using errcode = '42501';
  end if;

  select count(*) into used from public.products where brand_id = p_brand;

  if used > 0 then
    raise exception 'У марки % товаров — сначала объедините её с другой', used
      using errcode = '23503';
  end if;

  delete from public.brands where id = p_brand;

  if not found then
    raise exception 'Марка не найдена' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.admin_brands()                      from anon;
revoke all on function public.admin_rename_brand(bigint, text)    from anon;
revoke all on function public.admin_merge_brands(bigint, bigint)  from anon;
revoke all on function public.admin_delete_brand(bigint)          from anon;

grant execute on function public.admin_brands()                     to authenticated;
grant execute on function public.admin_rename_brand(bigint, text)   to authenticated;
grant execute on function public.admin_merge_brands(bigint, bigint) to authenticated;
grant execute on function public.admin_delete_brand(bigint)         to authenticated;
