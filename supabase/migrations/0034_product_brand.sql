-- ============================================================================
-- 0034. Марка товара из кабинета поставщика.
--
-- Зачем. В форме товара поля марки нет вообще, а марка при этом проставлена
-- и местами неверно: проверено на живой базе 19.09.2026 — «Переключатель
-- SCHNEIDER ELECTRIC AtlasDesign» числится под маркой Cersanit (сантехника),
-- строка «Розетки» — под Estima (керамогранит). В карточке покупатель видит
-- «CERSANIT · Переключатель Schneider Electric», и одна такая строка бьёт по
-- доверию ко всему каталогу сильнее, чем помогают десять правильных.
--
-- Почему функцией, а не политикой на insert. У brands включён RLS и есть
-- ровно одна политика — «read brands». Вставлять марки поставщик не может,
-- и открывать ему таблицу настежь не стоит: свободный ввод — это как раз
-- дорога к десяти написаниям «Kerama Marazzi». Функция нормализует имя,
-- ищет уже существующую марку без учёта регистра и только потом заводит
-- новую. Другого пути создать марку по-прежнему нет.
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

-- Без этого «Cersanit», «cersanit» и «CERSANIT » станут тремя марками,
-- и сравнение цен по марке развалится. На текущих шести именах конфликта
-- нет — проверено перед применением.
create unique index if not exists brands_name_uniq
  on public.brands (lower(btrim(name)));

-- Поставить товару марку по названию. Пустая строка или null — снять марку.
-- Возвращает id марки (или null, если сняли).
create or replace function public.set_product_brand(
  p_product bigint,
  p_brand   text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  n   text := nullif(btrim(coalesce(p_brand, '')), '');
  bid bigint;
begin
  if auth.uid() is null then
    raise exception 'Нужно войти в аккаунт' using errcode = '28000';
  end if;

  -- Менять марку может владелец карточки или администратор. Поставщик,
  -- который просто выставил свою цену на чужую карточку, к её содержимому
  -- отношения не имеет: карточка общая, и переписывать её ему нельзя.
  if not exists (
    select 1 from public.products p
     where p.id = p_product
       and (p.owner_id = auth.uid()
            or exists (select 1 from public.profiles pr
                        where pr.id = auth.uid() and pr.role = 'admin'))
  ) then
    raise exception 'Марку можно менять только у своих товаров'
      using errcode = '42501';
  end if;

  if n is null then
    update public.products set brand_id = null where id = p_product;
    return null;
  end if;

  -- Сначала ищем существующую: «kerama marazzi» и «Kerama Marazzi» —
  -- одна и та же марка, заводить вторую нельзя.
  select id into bid
    from public.brands
   where lower(btrim(name)) = lower(n)
   limit 1;

  if bid is null then
    insert into public.brands (name) values (n) returning id into bid;
  end if;

  update public.products set brand_id = bid where id = p_product;
  return bid;
end;
$$;

revoke all on function public.set_product_brand(bigint, text) from anon;
grant execute on function public.set_product_brand(bigint, text) to authenticated;
