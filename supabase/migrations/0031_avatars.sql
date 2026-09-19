-- ============================================================================
-- 0031. Аватарки людей и логотипы компаний.
--
-- ВАЖНО, вопреки записи в CLAUDE.md. Там сказано, что колонки avatar_url и
-- logo_url «в базе уже есть» и не хватает только бакета. Это верно для схемы
-- из репозитория, где профиль лежит в public.users, и неверно для живой базы:
-- проверено запросом 19.09.2026 — во всём public есть только
-- categories.image_url и products.image_url, ни avatar_url, ни logo_url нет.
-- Модели AppUser.avatarUrl и Supplier.logoUrl их читают, поэтому до сих пор
-- оба поля молча были null, и показывать было нечего.
--
-- Бакетов в живой базе тоже два: category-images и product-images.
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

-- ─────────────────────────── Колонки ───────────────────────────

alter table public.profiles  add column if not exists avatar_url text;
alter table public.suppliers add column if not exists logo_url   text;

comment on column public.profiles.avatar_url is
  'Фото пользователя. Публичная ссылка на файл в бакете avatars.';
comment on column public.suppliers.logo_url is
  'Логотип компании. Публичная ссылка на файл в бакете avatars.';

-- ─────────────────────────── Хранилище ───────────────────────────
--
-- Один бакет на людей и компании, а не два. Права одинаковые — «свою папку
-- пишет владелец, читают все», — и разводить две копии одних и тех же
-- четырёх политик значит однажды поправить одну и забыть вторую.
-- Внутри раскладка /<uid>/user_*.jpg и /<uid>/supplier_*.jpg.
--
-- Публичный: аватарка продавца видна в каталоге и на карте гостю,
-- который ещё не заводил аккаунт.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Чтение — всем
drop policy if exists "avatars_read" on storage.objects;
create policy "avatars_read" on storage.objects
  for select using (bucket_id = 'avatars');

-- Загрузка — авторизованным, каждый в свою папку /<uid>/...
drop policy if exists "avatars_insert" on storage.objects;
create policy "avatars_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Замена и удаление — только своих файлов
drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ─────────────────────────── Поставщики на карте ───────────────────────────
--
-- Правки функции nearby_suppliers здесь нет, и это не забывчивость.
-- CLAUDE.md говорит, что логотип отдаёт RPC nearby_suppliers. Проверено
-- 19.09.2026: такой функции в живой базе нет вовсе, а карта её и не зовёт —
-- SupplierRepository.nearby() берёт suppliers обычным select() и считает
-- расстояние в приложении по формуле гаверсинуса, без PostGIS.
--
-- Отсюда важное следствие: select() без списка колонок возвращает всё, и
-- новый logo_url доедет до карты и витрины сам, как только будет заполнен.
-- Ничего дописывать не нужно.
