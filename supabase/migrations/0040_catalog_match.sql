-- ============================================================
-- КОМПЛЕКТ · 0040 — склейка карточек каталога: ключ и алиасы
--
-- Зачем. Сравнение цен работает только если один товар у двух
-- поставщиков стал ОДНОЙ карточкой с двумя предложениями. Модель
-- заведена в 0013 (`products` — карточка, `offers` — цена продавца,
-- ключ — заводской артикул), но склеивалось почти ничего:
--
--   1. артикул сравнивался буква в букву, поэтому «DD-640200 R»,
--      «dd640200r» и «DD640200R» были тремя разными товарами;
--   2. у товаров без артикула (цемент, песок, штукатурка — у них
--      заводского артикула не бывает) ключа не было вовсе.
--
-- Клиент уже нормализует артикул сам (`sku_match.dart`, CLAUDE.md §6.6).
-- Эта миграция переносит то же правило в базу: один раз и для всех,
-- включая будущий импорт из Telegram mini-app.
--
-- Проверка администратора везде через public.profiles: таблицы
-- public.users в живой базе НЕТ (CLAUDE.md §6.1).
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run,
-- либо Actions → «Миграция базы» → 0040_catalog_match.sql.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Нормализация
--
-- Правило ровно то же, что в normSku/normName на клиенте: верхний
-- регистр, из артикула выброшено всё, кроме букв и цифр. Разойдутся
-- эти два правила — импорт снова начнёт плодить дубли, поэтому любая
-- правка здесь требует правки sku_match.dart, и наоборот.
--
-- Кириллица сохраняется: «ЦЕМ-М400» — такой же артикул, как
-- латинский. Ё вне диапазона А-Я, поэтому указана отдельно.
-- ─────────────────────────────────────────────────────────────
create or replace function public.norm_sku(t text)
returns text
language sql
immutable
parallel safe
as $$
  select nullif(regexp_replace(upper(coalesce(t, '')), '[^0-9A-ZА-ЯЁ]', '', 'g'), '')
$$;

comment on function public.norm_sku(text) is
  'Артикул для склейки карточек: верхний регистр, без разделителей. '
  'Совпадает с normSku из sku_match.dart — менять только вместе.';

create or replace function public.norm_name(t text)
returns text
language sql
immutable
parallel safe
as $$
  select nullif(btrim(regexp_replace(upper(coalesce(t, '')), '\s+', ' ', 'g')), '')
$$;

comment on function public.norm_name(text) is
  'Название для склейки: верхний регистр, пробелы свёрнуты в один.';

-- ─────────────────────────────────────────────────────────────
-- 2. Ключи прямо в таблице
--
-- Генерируемые колонки, а не триггер: значение не может разойтись
-- с источником, даже если строку правят запросом мимо приложения.
-- ─────────────────────────────────────────────────────────────
alter table public.products
  add column if not exists sku_norm text
  generated always as (public.norm_sku(sku)) stored;

alter table public.products
  add column if not exists name_norm text
  generated always as (public.norm_name(name)) stored;

create index if not exists products_sku_norm_idx
  on public.products (sku_norm)
  where sku_norm is not null;

create index if not exists products_name_norm_idx
  on public.products (category_slug, name_norm)
  where name_norm is not null;

-- ─────────────────────────────────────────────────────────────
-- 3. Откуда карточка и кто её проверил
--
-- Сейчас название и фото публичной карточки определяет тот, кто
-- первым залил прайс: внутреннее «Керамогранит 60х60 беж DD6402 1с»
-- становится заголовком в каталоге. source='admin' помечает карточки
-- справочника — их импорт поставщика перетирать не должен.
-- ─────────────────────────────────────────────────────────────
alter table public.products
  add column if not exists source text not null default 'supplier',
  add column if not exists verified_at timestamptz,
  add column if not exists verified_by uuid references auth.users(id);

do $$
begin
  alter table public.products
    add constraint products_source_check
    check (source in ('supplier', 'admin', 'import'));
exception
  when duplicate_object then null;   -- ограничение уже есть
  when check_violation then
    raise notice 'В products.source есть значения вне списка — ограничение не добавлено';
end $$;

-- ─────────────────────────────────────────────────────────────
-- 4. Алиасы: чем ЕЩЁ зовут этот товар
--
-- Нужны после слияния дублей (0041). Без них следующий импорт того
-- же прайса заведёт удалённую карточку заново — артикул-то в файле
-- не изменился, — и работа администратора обнулится.
--
-- Писать их может только merge_products (security definer): дать
-- клиентам право вписывать алиасы — значит дать переподвязывать
-- чужие товары к своим карточкам.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.product_aliases (
  id         bigint generated always as identity primary key,
  product_id bigint not null references public.products(id) on delete cascade,
  kind       text   not null check (kind in ('sku', 'name')),
  value_norm text   not null,
  created_at timestamptz not null default now(),
  unique (kind, value_norm)
);

create index if not exists product_aliases_product_idx
  on public.product_aliases (product_id);

alter table public.product_aliases enable row level security;

-- Читать можно всем: по алиасу ищет импорт, а он идёт от имени
-- поставщика. Политик на запись нет намеренно — см. выше.
drop policy if exists product_aliases_read on public.product_aliases;
create policy product_aliases_read on public.product_aliases
  for select using (true);

-- ─────────────────────────────────────────────────────────────
-- 5. Склейка по артикулу — одним запросом на весь прайс
--
-- Клиент раньше угадывал написание: спрашивал артикул в нескольких
-- регистрах и сравнивал на своей стороне. Здесь сравнение идёт по
-- нормализованной колонке, то есть покрывает все написания сразу.
--
-- Имена выходных колонок (key_norm, match_id) нарочно не совпадают
-- с именами колонок таблиц: иначе «column reference is ambiguous»
-- (та же грабля, что в 0035).
--
-- Если на один артикул пришлось несколько карточек (дубли ещё не
-- разобраны), берём лучшую: сначала справочник, потом ту, где больше
-- предложений. Склеивать дубли сама функция не вправе — это 0041.
-- ─────────────────────────────────────────────────────────────
create or replace function public.match_products_by_sku(p_skus text[])
returns table (key_norm text, match_id bigint)
language sql
stable
security definer
set search_path = public
as $$
  with keys as (
    select distinct public.norm_sku(s) as k
      from unnest(coalesce(p_skus, array[]::text[])) as s
     where public.norm_sku(s) is not null
  ),
  found as (
    select k.k as key_norm,
           coalesce(
             (select p.id
                from public.products p
               where p.sku_norm = k.k
               order by (p.source = 'admin') desc,
                        (select count(*) from public.offers o
                          where o.product_id = p.id) desc,
                        p.id
               limit 1),
             (select a.product_id
                from public.product_aliases a
               where a.kind = 'sku' and a.value_norm = k.k
               limit 1)
           ) as match_id
      from keys k
  )
  select f.key_norm, f.match_id from found f where f.match_id is not null
$$;

revoke all on function public.match_products_by_sku(text[]) from public;
grant execute on function public.match_products_by_sku(text[]) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 6. Склейка по названию — для товаров без артикула
--
-- Это и есть «цемент, песок, краска»: артикула у них нет, а карточка
-- всё равно должна быть одна.
--
-- Правило нарочно строгое: совпадение ТОЧНОЕ (после нормализации),
-- в пределах одной категории, и только если подходящая карточка
-- РОВНО ОДНА. Два кандидата — значит название неразличающее, и
-- угадывать нельзя: ошибочно слитые товары дороже лишнего дубля,
-- а разослать уведомление о «снижении цены» на чужой товар — ещё
-- дороже. Похожие (а не совпадающие) названия — отдельная задача
-- с подтверждением человеком, автоматом их склеивать нельзя.
-- ─────────────────────────────────────────────────────────────
create or replace function public.match_products_by_name(
  p_names    text[],
  p_category text
)
returns table (key_norm text, match_id bigint)
language sql
stable
security definer
set search_path = public
as $$
  with keys as (
    select distinct public.norm_name(n) as k
      from unnest(coalesce(p_names, array[]::text[])) as n
     where public.norm_name(n) is not null
  ),
  cand as (
    select k.k as key_norm,
           p.id as match_id,
           count(*) over (partition by k.k) as cnt
      from keys k
      join public.products p
        on p.name_norm = k.k
       and coalesce(p.category_slug, '') = coalesce(p_category, '')
  )
  select c.key_norm, c.match_id from cand c where c.cnt = 1
$$;

revoke all on function public.match_products_by_name(text[], text) from public;
grant execute on function public.match_products_by_name(text[], text) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 7. Защитный индекс — только если дублей нет
--
-- 0013 создавала его внутри do-блока с «exception when
-- unique_violation then raise notice», то есть при существующих
-- дублях индекс молча не создавался и ничего не защищал. Здесь
-- честно: сначала считаем дубли и говорим сколько их.
--
-- Индекс создаёт отдельная миграция 0042 — после разбора дублей
-- во вкладке «Дубли» админки.
-- ─────────────────────────────────────────────────────────────
do $$
declare groups int;
begin
  select count(*) into groups
    from (select 1
            from public.products
           where sku_norm is not null
           group by coalesce(brand_id, -1), sku_norm
          having count(*) > 1) t;

  if groups = 0 then
    raise notice 'Дублей по артикулу нет — можно применять 0042 (защитный индекс)';
  else
    raise notice 'Карточек-дублей по артикулу: % групп. Разберите их во вкладке «Дубли» админки, затем примените 0042', groups;
  end if;
end $$;
