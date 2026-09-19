-- ============================================================================
-- 0029. Остаток, срок поставки и техданные товара.
--
-- Зачем: в макете обещано «Остаток: 142 м²», «Под заказ (3 дня)»,
-- «Калькулятор упаковки: 2.22 м²», «Гарантия: 5 лет», «Матовая фактура · R10».
-- Ни одного из этих полей в базе не было — только булев offers.in_stock.
-- Пока их нет, любая такая строка на экране — выдумка.
--
-- Что добавляем и почему именно так:
--
--   offers.stock_qty       — остаток У КОНКРЕТНОГО поставщика, в единицах
--                            товара (products.unit). Остаток не свойство
--                            товара: у одного он есть, у другого нет.
--   offers.lead_time_days  — через сколько дней привезёт. 0 — со склада,
--                            null — поставщик не указал (а не «ноль дней»).
--
--   products.pack_qty      — сколько единиц в упаковке: плитка продаётся
--                            коробками, ламинат пачками. Без этого числа
--                            «нужно 38 м²» не превращается в «купить 7 пачек».
--   products.warranty_months — гарантия. В месяцах, а не годах: у смесителей
--                            она бывает 6 и 18 месяцев.
--   products.attrs         — остальные технические признаки свободным
--                            набором (фактура, класс износостойкости,
--                            ректификация, колеровка). Отдельные колонки
--                            под них завести нельзя: у плитки и у краски
--                            наборы разные, а таблица одна.
--
-- Заполняет поставщик в своём кабинете. Пустое значение — норма: экран
-- просто не покажет строку, вместо того чтобы соврать.
--
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

alter table public.offers
  add column if not exists stock_qty      numeric(12,2),
  add column if not exists lead_time_days int;

alter table public.offers
  drop constraint if exists offers_stock_qty_positive;
alter table public.offers
  add constraint offers_stock_qty_positive
  check (stock_qty is null or stock_qty >= 0);

alter table public.offers
  drop constraint if exists offers_lead_time_sane;
alter table public.offers
  add constraint offers_lead_time_sane
  check (lead_time_days is null or (lead_time_days >= 0 and lead_time_days <= 180));

comment on column public.offers.stock_qty is
  'Остаток у этого поставщика в единицах товара. Null — не указан';
comment on column public.offers.lead_time_days is
  'Срок поставки в днях. 0 — со склада, null — поставщик не указал';

alter table public.products
  add column if not exists pack_qty        numeric(12,3),
  add column if not exists warranty_months int,
  add column if not exists attrs           jsonb;

alter table public.products
  drop constraint if exists products_pack_qty_positive;
alter table public.products
  add constraint products_pack_qty_positive
  check (pack_qty is null or pack_qty > 0);

comment on column public.products.pack_qty is
  'Единиц товара в одной упаковке (м² в коробке, штук в пачке). Нужно, '
  'чтобы из потребности в м² посчитать, сколько упаковок покупать';
comment on column public.products.warranty_months is
  'Гарантия в месяцах — у смесителей бывает 6 и 18, годами не выразить';
comment on column public.products.attrs is
  'Технические признаки списком: фактура, класс износостойкости, '
  'ректификация, колеровка. Показываются чипами в карточке товара';

-- Право на запись не трогаем: политики offers и products уже разрешают
-- изменять только свои строки (0001, enforce_offer_owner). Новые колонки
-- подпадают под них автоматически.
