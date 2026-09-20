-- ============================================================
-- КОМПЛЕКТ · 0039 — рассылка уведомлений всем, кто установил приложение
--
-- Зачем. До сих пор отправить объявление можно было только из консоли
-- Firebase — то есть из чужого дашборда, без сегментов по роли и без
-- следов о том, что и когда отправляли. Здесь появляется своя кнопка
-- в админке: заголовок, текст, кому, и запись в журнал.
--
-- Что тут есть:
--   broadcasts                  — журнал отправок (кто, что, скольким);
--   admin_broadcast_audience()  — сколько устройств получит, для показа
--                                 ДО отправки (рассылку не отменить);
--   broadcast_targets()         — сами токены, только для service_role:
--                                 её зовёт Edge Function send-broadcast.
--
-- Сегменты: 'all' | 'suppliers' | 'clients'. Роль берём из profiles —
-- таблицы public.users в живой базе нет (CLAUDE.md §6.1).
-- ============================================================

create table if not exists public.broadcasts (
  id          bigserial primary key,
  title       text        not null,
  body        text        not null,
  segment     text        not null default 'all',
  -- Сколько токенов было на момент отправки и сколько из них приняло FCM.
  -- Разница — это удалённые приложения и протухшие токены; она нормальна,
  -- и видеть её полезно: если delivered резко меньше recipients, значит
  -- база токенов засорилась.
  recipients  integer     not null default 0,
  delivered   integer     not null default 0,
  failed      integer     not null default 0,
  status      text        not null default 'sending', -- sending | done | error
  error       text,
  created_by  uuid        references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create index if not exists broadcasts_created_at_idx
  on public.broadcasts (created_at desc);

alter table public.broadcasts enable row level security;

-- Журнал виден только администратору. Пишет в него Edge Function
-- с правами service_role — политики на неё не распространяются.
drop policy if exists broadcasts_admin_read on public.broadcasts;
create policy broadcasts_admin_read on public.broadcasts
  for select using (
    exists (select 1 from public.profiles p
             where p.id = auth.uid() and p.role = 'admin')
  );

-- ─────────────────────────────────────────────────────────────
-- Сколько устройств получит рассылку
--
-- Показывается в подтверждении перед отправкой. Отправку не отменить и
-- не отозвать — человек должен видеть масштаб до того, как нажмёт, а не
-- узнать его из журнала после.
-- ─────────────────────────────────────────────────────────────
create or replace function public.admin_broadcast_audience(p_segment text)
returns integer
language sql
security definer
set search_path = public
as $$
  select count(*)::int
  from public.device_tokens d
  left join public.profiles p on p.id = d.user_id
  where exists (select 1 from public.profiles a
                 where a.id = auth.uid() and a.role = 'admin')
    and (
      p_segment = 'all'
      or (p_segment = 'suppliers' and p.role = 'supplier')
      -- left join и coalesce нарочно: у человека может не быть строки в
      -- profiles, и считать его «не клиентом» из-за этого неправильно.
      or (p_segment = 'clients' and coalesce(p.role, 'client') <> 'supplier')
    );
$$;

-- ─────────────────────────────────────────────────────────────
-- Токены получателей — только для Edge Function
--
-- Права отозваны у всех: токен устройства позволяет слать пуши именно
-- этому телефону, и отдавать список наружу нельзя даже администратору.
-- Считать аудиторию он может (функция выше), видеть токены — нет.
-- ─────────────────────────────────────────────────────────────
create or replace function public.broadcast_targets(p_segment text)
returns table (token text)
language sql
security definer
set search_path = public
as $$
  select d.token
  from public.device_tokens d
  left join public.profiles p on p.id = d.user_id
  where p_segment = 'all'
     or (p_segment = 'suppliers' and p.role = 'supplier')
     or (p_segment = 'clients' and coalesce(p.role, 'client') <> 'supplier');
$$;

revoke all on function public.broadcast_targets(text) from public;
revoke all on function public.broadcast_targets(text) from anon, authenticated;
grant execute on function public.broadcast_targets(text) to service_role;
