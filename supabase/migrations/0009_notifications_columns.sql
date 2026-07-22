-- ============================================================================
-- 0009. Колонки для уведомлений о снижении цены.
--
-- Приложение умеет работать и без них (порог хранится на устройстве,
-- список уведомлений запрашивается без is_read), но с ними:
--   • «прочитано / непрочитано» считается на сервере и одинаково
--     на всех устройствах пользователя;
--   • серверная функция рассылки видит порог каждого пользователя
--     и не шлёт лишнего.
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────
-- 1. Прочитано ли уведомление
-- ─────────────────────────────────────────────────────────────────────
alter table public.price_drops
  add column if not exists is_read boolean not null default false;

create index if not exists price_drops_unread_idx
  on public.price_drops (user_id) where not is_read;

-- Пользователь должен иметь право пометить своё уведомление прочитанным
drop policy if exists price_drops_update_own on public.price_drops;
create policy price_drops_update_own on public.price_drops
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 2. Настройки уведомлений в профиле
--    По умолчанию — уведомлять при снижении от 10%.
-- ─────────────────────────────────────────────────────────────────────
alter table public.profiles
  add column if not exists notify_price_drops boolean not null default true;

alter table public.profiles
  add column if not exists notify_threshold int not null default 10;

-- Разумные границы: 1..90 процентов
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_notify_threshold_range'
  ) then
    alter table public.profiles
      add constraint profiles_notify_threshold_range
      check (notify_threshold between 1 and 90);
  end if;
end $$;
