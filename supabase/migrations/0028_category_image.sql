-- ============================================================================
-- 0028. Фотография категории для крупных плиток на главной.
--
-- Зачем: в макете четыре верхние категории — это снимки материала во всю
-- плитку, и именно они делают экран похожим на каталог, а не на список
-- кнопок. Хранить было негде: у categories есть только иконка (`icon`,
-- в живой базе `emoji`), колонки под картинку нет.
--
-- Заполняется вручную — это контент, а не код. Либо ссылкой на файл в
-- Storage (бакет `category-images`, создаётся ниже), либо любым внешним
-- адресом. Пустое значение — норма: плитка тогда показывает иконку
-- водяным знаком, как сейчас.
--
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

alter table public.categories
  add column if not exists image_url text;

comment on column public.categories.image_url is
  'Фото материала для крупной плитки на главной. Null — плитка показывает '
  'иконку; каталог из-за незаполненного контента не ломается';

-- ── Бакет для картинок категорий ────────────────────────────────────────
--
-- Публичный на чтение: эти снимки видит и гость на главной, до всякого
-- входа. Загрузка — только администратору: категорий десять, меняются они
-- раз в год, и давать сюда запись поставщикам незачем.
insert into storage.buckets (id, name, public)
values ('category-images', 'category-images', true)
on conflict (id) do update set public = true;

drop policy if exists category_images_read on storage.objects;
create policy category_images_read on storage.objects
  for select using (bucket_id = 'category-images');

drop policy if exists category_images_admin_write on storage.objects;
create policy category_images_admin_write on storage.objects
  for all to authenticated
  using (
    bucket_id = 'category-images'
    and exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin')
  )
  with check (
    bucket_id = 'category-images'
    and exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin')
  );
