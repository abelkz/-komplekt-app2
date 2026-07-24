-- ============================================================================
-- 0020. Продвижение в топ: норма Pro + докупаемый Буст.
--
-- Было: promote_offer поднимал товар любому Pro без ограничений — топ
-- превращался в кашу. Стало:
--   • Pro — 3 бесплатных подъёма в месяц, на 1 или 3 дня;
--   • сверх нормы, на 7 дней или без подписки — покупается Буст (кредит).
--
-- Оплата Буста пока вне приложения: поставщик оставляет заявку, вы её
-- подтверждаете в панели, и кредиты появляются на балансе. Когда будет
-- эквайринг, подтверждение станет автоматическим.
-- ============================================================================

-- Сколько бесплатных подъёмов Pro даёт в календарный месяц.
create or replace function public.pro_free_boosts_per_month()
returns int language sql immutable as $fn$ select 3 $fn$;

-- ── История подъёмов: по ней считаем месячную норму Pro ─────────────────────
create table if not exists public.promotions (
  id          bigint generated always as identity primary key,
  offer_id    bigint not null references public.offers(id)    on delete cascade,
  supplier_id bigint references public.suppliers(id)          on delete set null,
  days        int not null,
  source      text not null check (source in ('pro_free', 'boost')),
  until       timestamptz not null,
  created_at  timestamptz not null default now()
);
create index if not exists promotions_supplier_month_idx
  on public.promotions (supplier_id, created_at desc);

-- ── Купленные кредиты: каждая строка — один доступный подъём на N дней ───────
create table if not exists public.boost_credits (
  id          bigint generated always as identity primary key,
  supplier_id bigint not null references public.suppliers(id) on delete cascade,
  days        int not null check (days in (1, 3, 7)),
  status      text not null default 'available'
              check (status in ('available', 'used')),
  created_at  timestamptz not null default now(),
  used_at     timestamptz
);
create index if not exists boost_credits_avail_idx
  on public.boost_credits (supplier_id) where status = 'available';

-- ── Заявки на покупку Буста (оплата пока вручную) ───────────────────────────
create table if not exists public.boost_orders (
  id          bigint generated always as identity primary key,
  supplier_id bigint not null references public.suppliers(id) on delete cascade,
  user_id     uuid not null references auth.users(id)         on delete cascade,
  days        int not null check (days in (1, 3, 7)),
  qty         int not null default 1 check (qty between 1 and 50),
  status      text not null default 'new'
              check (status in ('new', 'paid', 'declined')),
  created_at  timestamptz not null default now()
);
create index if not exists boost_orders_new_idx
  on public.boost_orders (created_at desc) where status = 'new';

alter table public.promotions   enable row level security;
alter table public.boost_credits enable row level security;
alter table public.boost_orders  enable row level security;

-- Поставщик видит своё; пишут только функции (security definer)
drop policy if exists promotions_own on public.promotions;
create policy promotions_own on public.promotions for select to authenticated
  using (exists (select 1 from public.suppliers s
                  where s.id = supplier_id and s.owner_id = auth.uid()));

drop policy if exists boost_credits_own on public.boost_credits;
create policy boost_credits_own on public.boost_credits for select to authenticated
  using (exists (select 1 from public.suppliers s
                  where s.id = supplier_id and s.owner_id = auth.uid()));

drop policy if exists boost_orders_own on public.boost_orders;
create policy boost_orders_own on public.boost_orders for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists boost_orders_admin on public.boost_orders;
create policy boost_orders_admin on public.boost_orders for all to authenticated
  using (exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.role = 'admin'));
