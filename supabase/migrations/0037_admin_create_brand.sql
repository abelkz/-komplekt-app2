-- ============================================================
-- КОМПЛЕКТ · 0037 — завести марку из админки
--
-- Зачем, если марка и так создаётся сама. В 0034 марку заводит поставщик,
-- вписав её в карточку СВОЕГО товара, — то есть завести «Knauf» нельзя,
-- пока в каталоге нет ни одного товара Knauf. А нужно ровно наоборот:
-- заранее положить в список правильное написание, чтобы поставщик выбрал
-- его из подсказок, а не изобрёл «кнауф», «КНАУФ» и «Knauf Kazakhstan».
--
-- Расплата за это — марки без товаров. Они безвредны: в каталоге такая
-- марка не показывается (brandsOf строит список по товарам), видна только
-- в подсказках формы и во вкладке «Марки», где стоит первой и её можно
-- удалить одним действием.
-- ============================================================

create or replace function public.admin_create_brand(p_name text)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  n   text := nullif(btrim(coalesce(p_name, '')), '');
  bid bigint;
begin
  if not exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin') then
    raise exception 'Только для администратора' using errcode = '42501';
  end if;

  if n is null then
    raise exception 'Название марки не может быть пустым' using errcode = '22023';
  end if;

  -- Сравнение без учёта регистра и пробелов — то же правило, что и в
  -- set_product_brand. Иначе «Knauf» и «knauf» разъедутся в две марки
  -- прямо здесь, а чинить это придётся объединением.
  select b.id into bid
  from public.brands b
  where lower(btrim(b.name)) = lower(n)
  limit 1;

  if bid is not null then
    raise exception 'Марка «%» уже есть', n using errcode = '23505';
  end if;

  insert into public.brands (name) values (n) returning id into bid;
  return bid;
end;
$$;

revoke all on function public.admin_create_brand(text) from anon;
grant execute on function public.admin_create_brand(text) to authenticated;
