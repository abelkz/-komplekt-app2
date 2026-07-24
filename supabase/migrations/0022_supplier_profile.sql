-- ============================================================================
-- 0022. Витрина поставщика: рейтинг, отзывы, год работы, «о компании».
--
-- У suppliers не было ни рейтинга, ни отзывов — витрина показывала 0.0 и
-- пустой профиль. Добавляем поля профиля и отдельные отзывы о поставщике
-- (у товара свои отзывы, у продавца — свои).
-- ============================================================================

alter table public.suppliers
  add column if not exists rating     numeric(3,2) not null default 0,
  add column if not exists since_year int,
  add column if not exists about      text;

comment on column public.suppliers.since_year is 'Год начала работы компании';
comment on column public.suppliers.about is 'Короткое описание компании для витрины';

-- ── Отзывы о поставщике ─────────────────────────────────────────────────────
create table if not exists public.supplier_reviews (
  id          bigint generated always as identity primary key,
  supplier_id bigint not null references public.suppliers(id) on delete cascade,
  user_id     uuid not null references auth.users(id)         on delete cascade,
  rating      int not null check (rating between 1 and 5),
  text        text,
  created_at  timestamptz not null default now(),
  unique (supplier_id, user_id)   -- один отзыв на поставщика от человека
);
create index if not exists supplier_reviews_idx
  on public.supplier_reviews (supplier_id, created_at desc);

alter table public.supplier_reviews enable row level security;

-- Читают все, пишет автор только свой
drop policy if exists supplier_reviews_read on public.supplier_reviews;
create policy supplier_reviews_read on public.supplier_reviews
  for select using (true);

drop policy if exists supplier_reviews_write on public.supplier_reviews;
create policy supplier_reviews_write on public.supplier_reviews
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── Пересчёт рейтинга поставщика по его отзывам ─────────────────────────────
create or replace function public.recalc_supplier_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  sid bigint := coalesce(new.supplier_id, old.supplier_id);
begin
  update public.suppliers s
     set rating = coalesce(
           (select round(avg(rating)::numeric, 2)
              from public.supplier_reviews where supplier_id = sid), 0)
   where s.id = sid;
  return null;
end;
$fn$;

drop trigger if exists supplier_reviews_recalc on public.supplier_reviews;
create trigger supplier_reviews_recalc
  after insert or update or delete on public.supplier_reviews
  for each row execute function public.recalc_supplier_rating();
