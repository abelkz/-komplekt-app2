-- ============================================================================
-- 0030. Сводка для владельца: что происходит в приложении.
--
-- Почему функциями в базе, а не запросами из приложения: RLS отдаёт строки,
-- а не агрегаты. Чтобы показать одно число «регистраций за месяц», клиенту
-- пришлось бы вытянуть все строки profiles и посчитать их у себя — это и
-- медленно, и отдаёт наружу персональные данные, которые показывать незачем.
-- Функции считают в базе и возвращают только итоги.
--
-- Все функции security definer, поэтому КАЖДАЯ сама проверяет, что зовущий —
-- администратор. Без этой проверки security definer обошёл бы RLS и отдал
-- статистику кому угодно.
--
-- Источники намеренно разные, и это не дублирование:
--   * app_events (0024) — продуктовые события, пишутся и от гостей: поиск,
--     открытие категории, открытие карточки товара;
--   * events (0003) — просмотры и обращения в разрезе товар+поставщик,
--     на них считается статистика в кабинете поставщика.
-- Проверено на живой базе 19.09.2026: в app_events лежат category_open
-- и product_view, в events — view и contact.
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

-- Проверка прав. Роль берём из public.profiles, а НЕ из public.users:
-- таблицы users в живой базе нет, она есть только в схеме из 0001_init.sql.
create or replace function public.admin_guard()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.role = 'admin') then
    raise exception 'Доступ только для администратора' using errcode = '42501';
  end if;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Сводка одной строкой за последние p_days дней.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public.admin_overview(p_days int default 30)
returns table (
  users_total       bigint,
  users_new         bigint,
  suppliers_total   bigint,
  suppliers_pending bigint,
  products_total    bigint,
  offers_total      bigint,
  searches          bigint,
  product_views     bigint,
  category_opens    bigint,
  contacts          bigint,
  favorites_total   bigint,
  paid_total        numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  since timestamptz := now() - make_interval(days => greatest(p_days, 1));
begin
  perform public.admin_guard();

  return query
  select
    (select count(*) from public.profiles),
    (select count(*) from public.profiles where created_at >= since),
    (select count(*) from public.suppliers),
    -- Ожидают решения — это же число висит счётчиком в профиле админа
    (select count(*) from public.profiles
      where role = 'supplier' and status = 'pending'),
    (select count(*) from public.products),
    (select count(*) from public.offers),
    (select count(*) from public.app_events
      where name = 'search' and created_at >= since),
    (select count(*) from public.app_events
      where name = 'product_view' and created_at >= since),
    (select count(*) from public.app_events
      where name = 'category_open' and created_at >= since),
    -- Обращения берём из events: именно они — обещанная поставщику отдача,
    -- и накоплены они с самого начала, а не с выката 1.0.1.
    (select count(*) from public.events
      where type = 'contact' and created_at >= since),
    (select count(*) from public.favorites),
    -- Оплаты. Три тонкости, каждая проверена по 0023 и по живой базе:
    --   * успешный статус называется 'paid' (не 'completed') — иначе сумма
    --     молча оставалась бы нулём навсегда;
    --   * период считаем по paid_at, а не created_at: счёт выставляется
    --     и оплачивается в разные моменты, иногда в разные месяцы;
    --   * amount в базе integer, а возвращаем numeric — без приведения
    --     sum() даёт bigint и тип не сойдётся с объявленным.
    (select coalesce(sum(amount), 0)::numeric from public.payments
      where status = 'paid' and paid_at >= since);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- По дням — для графика. Дни без событий тоже возвращаем нулями:
-- провал в графике должен быть виден как провал, а не как отсутствие точки.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public.admin_daily(p_days int default 30)
returns table (
  day           date,
  registrations bigint,
  product_views bigint,
  searches      bigint,
  contacts      bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  since timestamptz := now() - make_interval(days => greatest(p_days, 1));
begin
  perform public.admin_guard();

  return query
  with days as (
    select generate_series(since::date, now()::date, interval '1 day')::date as d
  )
  select
    days.d,
    (select count(*) from public.profiles p
      where p.created_at::date = days.d),
    (select count(*) from public.app_events e
      where e.name = 'product_view' and e.created_at::date = days.d),
    (select count(*) from public.app_events e
      where e.name = 'search' and e.created_at::date = days.d),
    (select count(*) from public.events v
      where v.type = 'contact' and v.created_at::date = days.d)
  from days
  order by days.d;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Что искали. Главный вопрос к каталогу: по этим строкам видно, каких
-- материалов и поставщиков не хватает.
--
-- Запрос приводим к нижнему регистру и режем пробелы — иначе «Плитка»,
-- «плитка» и «плитка » окажутся тремя разными строками в топе.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public.admin_top_searches(
  p_days  int default 30,
  p_limit int default 20
)
returns table (query text, n bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  since timestamptz := now() - make_interval(days => greatest(p_days, 1));
begin
  perform public.admin_guard();

  return query
  select lower(btrim(e.props ->> 'query')) as q, count(*) as cnt
    from public.app_events e
   where e.name = 'search'
     and e.created_at >= since
     and coalesce(btrim(e.props ->> 'query'), '') <> ''
   group by q
   order by cnt desc, q
   limit greatest(p_limit, 1);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Какие категории открывают, а какие лежат мёртвым грузом.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public.admin_top_categories(
  p_days  int default 30,
  p_limit int default 20
)
returns table (slug text, name text, n bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  since timestamptz := now() - make_interval(days => greatest(p_days, 1));
begin
  perform public.admin_guard();

  return query
  select s.slug,
         -- Категорию могли переименовать или удалить — тогда показываем slug,
         -- а не пустую строку: иначе строка в отчёте выглядит поломанной.
         coalesce(c.name, s.slug) as nm,
         s.cnt
    from (
      select e.props ->> 'slug' as slug, count(*) as cnt
        from public.app_events e
       where e.name = 'category_open'
         and e.created_at >= since
         and coalesce(e.props ->> 'slug', '') <> ''
       group by 1
    ) s
    left join public.categories c on c.slug = s.slug
   order by s.cnt desc, nm
   limit greatest(p_limit, 1);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Поставщики с их показателями — чтобы видеть, кто реально работает,
-- а кто завёл компанию и забыл.
--
-- Просмотры и обращения считаем по events: это ровно те числа, которые
-- поставщик видит у себя в кабинете, и расхождение между его экраном
-- и админкой было бы поводом для спора на пустом месте.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public.admin_suppliers(p_days int default 30)
returns table (
  supplier_id  bigint,
  name         text,
  city         text,
  plan         text,
  plan_until   timestamptz,
  verified     boolean,
  status       text,
  products     bigint,
  offers       bigint,
  views        bigint,
  contacts     bigint,
  last_price_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  since timestamptz := now() - make_interval(days => greatest(p_days, 1));
begin
  perform public.admin_guard();

  return query
  select
    s.id,
    s.name,
    s.city,
    s.plan,
    s.plan_until,
    coalesce(s.verified, false),
    s.status,
    (select count(distinct o.product_id) from public.offers o
      where o.supplier_id = s.id),
    (select count(*) from public.offers o where o.supplier_id = s.id),
    (select count(*) from public.events v
      where v.supplier_id = s.id and v.type = 'view' and v.created_at >= since),
    (select count(*) from public.events v
      where v.supplier_id = s.id and v.type = 'contact' and v.created_at >= since),
    -- Когда последний раз трогали прайс: мёртвый прайс хуже отсутствующего,
    -- потому что покупатель звонит по цене, которой уже нет.
    (select max(o.price_updated_at) from public.offers o
      where o.supplier_id = s.id)
  from public.suppliers s
  -- 11 — обращения, 10 — просмотры (по порядку колонок выше). Сортируем
  -- по обращениям: просмотр можно накрутить, звонок — это уже сделка.
  order by 11 desc, 10 desc, s.name;
end;
$$;

-- Звать может только вошедший пользователь; внутри каждая функция ещё раз
-- убеждается, что это администратор.
revoke all on function public.admin_overview(int)       from anon;
revoke all on function public.admin_daily(int)          from anon;
revoke all on function public.admin_top_searches(int,int) from anon;
revoke all on function public.admin_top_categories(int,int) from anon;
revoke all on function public.admin_suppliers(int)      from anon;

grant execute on function public.admin_overview(int)          to authenticated;
grant execute on function public.admin_daily(int)             to authenticated;
grant execute on function public.admin_top_searches(int,int)  to authenticated;
grant execute on function public.admin_top_categories(int,int) to authenticated;
grant execute on function public.admin_suppliers(int)         to authenticated;
