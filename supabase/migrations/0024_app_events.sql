-- ============================================================================
-- 0024. Продуктовая аналитика: что люди делают в приложении.
--
-- Зачем отдельная таблица, а не existing `events`: та считает просмотры и
-- контакты для статистики КОНКРЕТНОГО поставщика и жёстко привязана к паре
-- товар+поставщик. Здесь нужны события всего приложения — поиск, открытие
-- категории, экраны — в том числе от гостей, у которых нет ни аккаунта, ни
-- привязки к поставщику.
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

create table if not exists public.app_events (
  id         bigserial primary key,
  -- Гость пишет события с user_id = null: до регистрации воронка как раз и
  -- самая интересная. При удалении аккаунта событие остаётся обезличенным.
  user_id    uuid references auth.users(id) on delete set null,
  name       text not null,
  props      jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists app_events_name_created_idx
  on public.app_events (name, created_at desc);
create index if not exists app_events_created_idx
  on public.app_events (created_at desc);

alter table public.app_events enable row level security;

-- Писать может кто угодно, включая анонимного посетителя.
drop policy if exists app_events_insert on public.app_events;
create policy app_events_insert on public.app_events
  for insert with check (true);

-- Читать — только админ: это внутренняя статистика, не пользовательские данные.
--
-- Роль берём из public.profiles, а НЕ из public.users: в живой базе таблицы
-- users нет, она существует только в схеме из 0001_init.sql. Так же admin
-- проверяют все миграции после объединения схем — 0015, 0017, 0020, 0021.
drop policy if exists app_events_admin_read on public.app_events;
create policy app_events_admin_read on public.app_events
  for select to authenticated
  using (exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.role = 'admin'));

-- Править и удалять события нельзя никому из клиентов: журнал только дописывается.
revoke update, delete on public.app_events from anon, authenticated;
