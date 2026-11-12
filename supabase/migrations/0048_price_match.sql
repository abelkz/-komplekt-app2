-- ============================================================================
-- 0048. Сопоставление карточек с товарами магазина — руками, с глазами
--
-- ЗАЧЕМ. В каталоге 187 карточек справочника без единой цены. Привязать их
-- автоматически нельзя, и это проверено, а не предположено: справочник
-- (`0043`) брал названия со страниц товаров, а разбор берёт их из `alt`
-- картинки в списке раздела, и это разные написания одного товара:
--
--     у нас   Антисептик для дерева 2в1 Акватекс полуматовый Сосна 0,8л
--     у них   СОСТАВ АКВАТЕКС СОСНА 0,8Л
--
-- Сшивать по похожести НЕЛЬЗЯ. Поиск магазина по нашей карточке
-- «Dulux Diamond Max Protect мат BW 9л» отдаёт 1 л, 2,5 л и 10 л —
-- девятилитровой у него нет. Привязать цену десятилитровой банки к
-- карточке девятилитровой хуже, чем оставить «цена не указана»:
-- покупатель приедет в магазин и уедет злым. Это та же причина, по
-- которой в справочнике намеренно не проставляли артикулы (см. `0043`).
--
-- ЧТО ЗДЕСЬ. Машина только ПРЕДЛАГАЕТ: скрипт `tools/match_candidates.py`
-- обходит каталог магазина и кладёт сюда по несколько кандидатов на
-- карточку с ценой и ссылкой. Решение принимает человек во вкладке
-- «Сопоставление» админки. Пока кандидат не подтверждён, в каталоге
-- не меняется ничего.
--
-- Почему отдельная таблица, а не сразу предложения: предложение — это
-- цена, которую видит покупатель. Непроверенная догадка машины не должна
-- попадать туда даже на минуту.
-- ============================================================================

create table if not exists public.price_match_candidates (
  id          bigserial primary key,
  product_id  bigint not null references public.products(id) on delete cascade,
  supplier_id bigint not null references public.suppliers(id) on delete cascade,
  title       text   not null,          -- как товар называется у магазина
  price       numeric not null check (price > 0),
  url         text,
  score       real   not null default 0, -- похожесть названий, для порядка
  status      text   not null default 'pending'
              check (status in ('pending', 'accepted', 'rejected')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz,
  decided_by  uuid references auth.users(id) on delete set null
);

-- Один и тот же товар магазина не предлагается к одной карточке дважды.
create unique index if not exists price_match_candidates_uniq
  on public.price_match_candidates (product_id, supplier_id, title);

create index if not exists price_match_candidates_pending_idx
  on public.price_match_candidates (product_id, score desc)
  where status = 'pending';

comment on table public.price_match_candidates is
  'Предложенные машиной пары «наша карточка ↔ товар магазина». Решает '
  'человек во вкладке «Сопоставление»: до подтверждения в каталоге '
  'не меняется ничего';


-- ──────────────────────────── права ────────────────────────────
-- Читает и решает только администратор. Наполняет таблицу скрипт с
-- секретным ключом — он ходит мимо политик.

alter table public.price_match_candidates enable row level security;

drop policy if exists price_match_admin_read on public.price_match_candidates;
create policy price_match_admin_read on public.price_match_candidates
  for select using (
    exists (select 1 from public.profiles p
             where p.id = auth.uid() and p.role = 'admin')
  );


-- ─────────────────── что показывать администратору ───────────────────

create or replace function public.admin_match_queue(p_limit int default 50)
returns table (
  product_id    bigint,
  product_name  text,
  category_slug text,
  image_url     text,
  candidates    jsonb
)
language sql
security definer
set search_path = public
stable
as $$
  select p.id,
         p.name,
         p.category_slug,
         p.image_url,
         jsonb_agg(jsonb_build_object(
           'id',    c.id,
           'title', c.title,
           'price', c.price,
           'url',   c.url,
           'score', c.score
         ) order by c.score desc, c.price)
    from public.price_match_candidates c
    join public.products p on p.id = c.product_id
   where c.status = 'pending'
     and exists (select 1 from public.profiles pr
                  where pr.id = auth.uid() and pr.role = 'admin')
     -- карточка могла получить цену другим путём, пока очередь ждала
     and not exists (select 1 from public.offers o where o.product_id = p.id)
   group by p.id
   order by p.category_slug, p.name
   limit greatest(p_limit, 1);
$$;

revoke all on function public.admin_match_queue(int) from public;
grant execute on function public.admin_match_queue(int) to authenticated;

comment on function public.admin_match_queue(int) is
  'Очередь сопоставления: карточка без цены и предложенные к ней товары '
  'магазина. Карточки, успевшие получить цену, из очереди выпадают';


-- ──────────────────────── решение человека ────────────────────────

create or replace function public.admin_accept_match(p_candidate bigint)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  me   uuid := auth.uid();
  cand public.price_match_candidates%rowtype;
  new_offer bigint;
begin
  if not exists (select 1 from public.profiles p
                 where p.id = me and p.role = 'admin') then
    raise exception 'Только для администратора' using errcode = '42501';
  end if;

  select * into cand from public.price_match_candidates
   where id = p_candidate and status = 'pending';
  if not found then
    raise exception 'Кандидат % не найден или уже разобран', p_candidate
      using errcode = 'P0002';
  end if;

  -- Цена поставщика на эту карточку уже могла появиться: тогда ничего
  -- не заводим, а кандидата закрываем — задача выполнена без нас.
  select o.id into new_offer from public.offers o
   where o.product_id = cand.product_id
     and o.supplier_id = cand.supplier_id
   limit 1;

  if new_offer is null then
    insert into public.offers (product_id, supplier_id, price, in_stock,
                               product_url)
    values (cand.product_id, cand.supplier_id, cand.price, true, cand.url)
    returning id into new_offer;
  end if;

  update public.price_match_candidates
     set status = 'accepted', decided_at = now(), decided_by = me
   where id = cand.id;

  -- Остальные кандидаты этой карточки от того же магазина больше не нужны:
  -- товар выбран, второй цены от того же продавца быть не может.
  update public.price_match_candidates
     set status = 'rejected', decided_at = now(), decided_by = me
   where product_id = cand.product_id
     and supplier_id = cand.supplier_id
     and status = 'pending'
     and id <> cand.id;

  return new_offer;
end;
$$;

revoke all on function public.admin_accept_match(bigint) from public;
grant execute on function public.admin_accept_match(bigint) to authenticated;


create or replace function public.admin_reject_match(
  p_product  bigint,
  p_supplier bigint default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  n  int;
begin
  if not exists (select 1 from public.profiles p
                 where p.id = me and p.role = 'admin') then
    raise exception 'Только для администратора' using errcode = '42501';
  end if;

  update public.price_match_candidates
     set status = 'rejected', decided_at = now(), decided_by = me
   where product_id = p_product
     and (p_supplier is null or supplier_id = p_supplier)
     and status = 'pending';
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.admin_reject_match(bigint, bigint) from public;
grant execute on function public.admin_reject_match(bigint, bigint) to authenticated;

comment on function public.admin_reject_match(bigint, bigint) is
  '«Ничего не подходит»: закрывает все предложения по карточке. Сама '
  'карточка остаётся в каталоге без цены — это законное состояние';
