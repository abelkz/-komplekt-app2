-- ============================================================================
-- 0018. История цен — то, за что платит дизайнер в тарифе Про.
--
-- В 0012 мы запоминали только прошлую цену (offers.prev_price): видно
-- «было/стало», но не видно, как цена вела себя месяц назад. Здесь
-- появляется полноценная лента изменений по каждому предложению.
--
-- Читать историю может владелец предложения и тот, у кого действует
-- тариф Про — гейт стоит в RLS, а не только на экране.
-- ============================================================================

create table if not exists public.price_history (
  id          bigint generated always as identity primary key,
  offer_id    bigint not null references public.offers(id)    on delete cascade,
  product_id  bigint not null references public.products(id)  on delete cascade,
  supplier_id bigint references public.suppliers(id)          on delete set null,
  price       numeric(12,2) not null,
  changed_at  timestamptz not null default now()
);

create index if not exists price_history_product_idx
  on public.price_history (product_id, changed_at desc);
create index if not exists price_history_offer_idx
  on public.price_history (offer_id, changed_at desc);

alter table public.price_history enable row level security;

-- Свою историю поставщик видит всегда
drop policy if exists price_history_owner on public.price_history;
create policy price_history_owner on public.price_history
  for select to authenticated
  using (exists (select 1 from public.offers o
                  where o.id = offer_id and o.owner_id = auth.uid()));

-- Остальным — по тарифу
drop policy if exists price_history_pro on public.price_history;
create policy price_history_pro on public.price_history
  for select to authenticated
  using (exists (select 1 from public.profiles p
                  where p.id = auth.uid()
                    and (p.role = 'admin'
                         or public.plan_active(p.plan, p.plan_until))));

-- Пишет только триггер (security definer), напрямую — никто
revoke insert, update, delete on public.price_history from authenticated, anon;

-- ── Запись изменений ────────────────────────────────────────────────────────
create or replace function public.price_history_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if TG_OP = 'UPDATE' and new.price is not distinct from old.price then
    return new;
  end if;

  insert into public.price_history (offer_id, product_id, supplier_id, price)
  values (new.id, new.product_id, new.supplier_id, new.price);

  return new;
end;
$fn$;

drop trigger if exists price_history_write on public.offers;
create trigger price_history_write
  after insert or update of price on public.offers
  for each row execute function public.price_history_write();

-- Стартовая точка: текущие цены, чтобы график был не пустым с первого дня
insert into public.price_history (offer_id, product_id, supplier_id, price, changed_at)
select o.id, o.product_id, o.supplier_id, o.price,
       coalesce(o.price_updated_at, now())
  from public.offers o
 where o.price is not null
   and not exists (select 1 from public.price_history h where h.offer_id = o.id);

comment on table public.price_history is
  'Лента изменений цен. Доступна на чтение владельцу предложения и '
  'пользователям с активным тарифом Про';
