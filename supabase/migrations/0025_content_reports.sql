-- ============================================================================
-- 0025. Жалобы на пользовательский контент.
--
-- Приложение уже умеет жаловаться на отзывы (ReportMenu в
-- lib/core/moderation/review_moderation.dart) и пишет в content_reports,
-- но самой таблицы не было: insert падал в пустой catch, человек видел
-- «Жалоба отправлена», а до администратора ничего не доходило.
--
-- Локальное скрытие отзыва у пожаловавшегося работало и без неё — этого
-- хватило для ревью App Store (Guideline 1.2), но фактической модерации
-- не было.
--
-- Применять: Actions → «Миграция базы» → Run workflow → 0025_content_reports.sql
-- Либо вручную: Supabase → SQL Editor → вставить целиком → Run.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

create table if not exists public.content_reports (
  id          bigserial primary key,

  -- Откуда отзыв. Жаловаться можно и на отзыв о товаре, и на отзыв
  -- о поставщике — таблицы разные.
  target      text not null
              check (target in ('product_review', 'supplier_review')),

  -- Идентификатор отзыва хранится ТЕКСТОМ, и это намеренно: у reviews.id
  -- тип uuid, а у supplier_reviews.id — bigint. Одной типизированной
  -- колонкой оба не покрыть, а внешний ключ невозможен, потому что
  -- ссылаться пришлось бы сразу на две таблицы. Куда смотреть, говорит
  -- колонка target.
  review_id   text not null,

  -- Кто пожаловался. Гость тоже может — каталог и отзывы открыты всем,
  -- у него будет null. При удалении аккаунта жалоба остаётся обезличенной.
  reporter_id uuid references auth.users(id) on delete set null,

  reason      text not null default 'objectionable',

  -- Что с жалобой сделали. Меняет только администратор.
  status      text not null default 'new'
              check (status in ('new', 'reviewed', 'removed', 'rejected')),

  created_at  timestamptz not null default now()
);

-- Разбор начинается с новых жалоб, поэтому индекс по статусу и дате.
create index if not exists content_reports_status_idx
  on public.content_reports (status, created_at desc);

-- Чтобы видеть, на какой отзыв уже жаловались.
create index if not exists content_reports_target_idx
  on public.content_reports (target, review_id);

alter table public.content_reports enable row level security;

-- Пожаловаться может кто угодно, включая анонимного посетителя: отзывы
-- видны без регистрации, значит и жаловаться на них можно без неё.
drop policy if exists content_reports_insert on public.content_reports;
create policy content_reports_insert on public.content_reports
  for insert with check (true);

-- Читать и разбирать — только администратор.
--
-- Роль берём из public.profiles: таблицы public.users в живой базе нет
-- (см. CLAUDE.md §6.1).
drop policy if exists content_reports_admin_read on public.content_reports;
create policy content_reports_admin_read on public.content_reports
  for select to authenticated
  using (exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.role = 'admin'));

drop policy if exists content_reports_admin_update on public.content_reports;
create policy content_reports_admin_update on public.content_reports
  for update to authenticated
  using (exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.role = 'admin'))
  with check (exists (select 1 from public.profiles p
                       where p.id = auth.uid() and p.role = 'admin'));

-- Удалять жалобы клиентам нельзя: разбор ведётся сменой статуса.
revoke delete on public.content_reports from anon, authenticated;

comment on table public.content_reports is
  'Жалобы на отзывы (App Store Guideline 1.2). Разбираются администратором '
  'сменой статуса; review_id текстовый, потому что отзывы о товарах имеют '
  'uuid, а о поставщиках — bigint';

-- ────────────────────────────────────────────────────────────────────────
-- Удаление отзыва администратором.
--
-- Через клиент это невозможно: политики reviews и supplier_reviews дают
-- право удалять только автору. Без такой функции экран разбора жалоб был бы
-- бутафорией — статус меняется, а оскорбительный отзыв остаётся висеть.
--
-- Заодно закрывает все жалобы на этот отзыв, чтобы он не всплыл в списке
-- второй раз.
-- ────────────────────────────────────────────────────────────────────────
create or replace function public.admin_delete_review(
  p_target    text,
  p_review_id text
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.role = 'admin') then
    raise exception 'Доступно только администратору';
  end if;

  -- Тип идентификатора зависит от таблицы: uuid у отзывов о товарах,
  -- bigint у отзывов о поставщиках.
  if p_target = 'product_review' then
    delete from public.reviews where id = p_review_id::uuid;
  elsif p_target = 'supplier_review' then
    delete from public.supplier_reviews where id = p_review_id::bigint;
  else
    raise exception 'Неизвестный тип отзыва: %', p_target;
  end if;

  update public.content_reports
     set status = 'removed'
   where target = p_target and review_id = p_review_id;
end;
$$;

revoke all on function public.admin_delete_review(text, text) from public;
grant execute on function public.admin_delete_review(text, text) to authenticated;
