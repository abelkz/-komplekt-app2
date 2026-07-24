-- ============================================================================
-- 0019. Место поставщика на карте.
--
-- У живой таблицы suppliers не было ни адреса, ни координат, поэтому карта
-- «поставщики рядом» была пустой. Добавляем адрес и точку (lat/lng).
--
-- PostGIS специально не используем: точек немного, расстояние приложение
-- считает само. Так надёжнее — не нужно расширение и права на него.
-- ============================================================================

alter table public.suppliers
  add column if not exists address text,
  add column if not exists lat double precision,
  add column if not exists lng double precision;

-- Владелец может править свою карточку (адрес и точку в том числе).
-- Если RLS выключен — политика не мешает; если включён — разрешает своё.
drop policy if exists suppliers_owner_update on public.suppliers;
create policy suppliers_owner_update on public.suppliers
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

comment on column public.suppliers.lat is
  'Широта точки компании на карте. Пусто — компании нет на карте';
comment on column public.suppliers.lng is 'Долгота точки компании на карте';
