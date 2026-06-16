-- ============================================================
-- КОМПЛЕКТ · Хранилище фото товаров (Supabase Storage) — миграция 0004
-- Бакет product-images (публичное чтение, загрузка — авторизованным).
-- Запускать ПОСЛЕ 0001_init.sql.
-- ============================================================

-- ── Публичный бакет для фото товаров ──
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

-- ── Политики доступа к объектам бакета ──
-- Чтение — всем (бакет публичный, фото видны в каталоге)
drop policy if exists "product_images_read" on storage.objects;
create policy "product_images_read" on storage.objects
  for select using (bucket_id = 'product-images');

-- Загрузка — любому авторизованному пользователю
drop policy if exists "product_images_insert" on storage.objects;
create policy "product_images_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-images');

-- Изменение/удаление — только владельцу файла
drop policy if exists "product_images_update_own" on storage.objects;
create policy "product_images_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'product-images' and owner = auth.uid());

drop policy if exists "product_images_delete_own" on storage.objects;
create policy "product_images_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-images' and owner = auth.uid());
