-- ============================================================================
-- 0008. Закрытие пользовательского контура: избранное и комплекты.
--
-- ПРОБЛЕМА, которую чиним:
--   на favorites/projects/project_items висит отладочная политика
--   «demo favorites» вида ALL / public / true — читать и писать может кто
--   угодно. Проверено: анонимным ключом видны чужие Telegram-ID, названия
--   проектов и полный состав спецификаций.
--
-- ⚠️ ПОРЯДОК ПРИМЕНЕНИЯ ВАЖЕН.
--   Эта миграция требует, чтобы у КАЖДОГО пользователя была сессия Supabase
--   (auth.uid()). Пока Telegram-приложение пишет от анонима по user_tg_id,
--   применение этого файла сломает сохранение избранного и комплектов.
--   Сначала включите сессии в приложении, убедитесь, что они работают,
--   и только потом выполняйте этот скрипт.
--
-- Каталог (products, offers, suppliers, brands, categories) не трогаем —
-- там политики уже корректные, привязаны к owner_id.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────
-- 1. Избранное — только своё
-- ─────────────────────────────────────────────────────────────────────
drop policy if exists "demo favorites" on public.favorites;
drop policy if exists favorites_own    on public.favorites;

alter table public.favorites enable row level security;

create policy favorites_own on public.favorites
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 2. Комплекты (проекты) — только свои
-- ─────────────────────────────────────────────────────────────────────
drop policy if exists "demo projects" on public.projects;
drop policy if exists projects_own    on public.projects;

alter table public.projects enable row level security;

create policy projects_own on public.projects
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 3. Позиции комплекта — доступны через владельца комплекта
-- ─────────────────────────────────────────────────────────────────────
drop policy if exists "demo project_items" on public.project_items;
drop policy if exists project_items_own    on public.project_items;

alter table public.project_items enable row level security;

create policy project_items_own on public.project_items
  for all to authenticated
  using (exists (select 1 from public.projects p
                 where p.id = project_id and p.user_id = auth.uid()))
  with check (exists (select 1 from public.projects p
                      where p.id = project_id and p.user_id = auth.uid()));

-- ─────────────────────────────────────────────────────────────────────
-- 4. Перенос старых записей на новый ключ
--
--    Строки, созданные до появления сессий, имеют только user_tg_id.
--    Их владельца достоверно определить нельзя, поэтому просто оставляем:
--    с включённой политикой они станут невидимы (user_id пуст).
--    Данных немного (единицы строк) — это осознанная потеря демо-данных,
--    а не рабочих. Если нужно сохранить конкретный проект, проставьте
--    ему user_id вручную ПЕРЕД применением политик, например:
--
--      update public.projects set user_id = '<uuid-пользователя>'
--       where id = 1;
-- ─────────────────────────────────────────────────────────────────────

-- Проверка после применения (должно вернуть 0 строк для анонима):
--   выполните из приложения без входа: select * from favorites;
