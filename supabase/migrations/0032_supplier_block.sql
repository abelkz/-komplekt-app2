-- ============================================================================
-- 0032. Блокировка и удаление поставщика.
--
-- Зачем отдельно от status. В живой базе у всех 17 компаний
-- suppliers.status = 'active', а модерация заявок в админке правит
-- profiles.status ('pending'/'approved'/'rejected') — это другая колонка и
-- другой смысл: «пустили ли компанию в систему». Блокировка за штраф или
-- жалобу — третье состояние: компания одобрена, но временно не показывается.
-- Мешать это со status значит однажды разблокировать вместе с одобрением.
--
-- Главное здесь — не колонка, а политики чтения. Проверено 19.09.2026:
-- «read offers», «read products» и «read suppliers» стоят на using (true),
-- то есть открыты всем. Без правки политик блокировка была бы только
-- надписью в админке: цены заблокированной компании продолжали бы
-- показываться в каталоге и на карте.
--
-- Применять: Supabase → SQL Editor → вставить целиком → Run.
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

alter table public.suppliers
  add column if not exists blocked_until timestamptz,
  add column if not exists blocked_at    timestamptz,
  add column if not exists block_reason  text;

comment on column public.suppliers.blocked_until is
  'До какого момента компания скрыта. NULL — не заблокирована. '
  'infinity — бессрочно. Прошедшая дата снимает блокировку сама.';
comment on column public.suppliers.block_reason is
  'Причина блокировки. Показывается самому поставщику в кабинете: '
  'человек должен понимать, за что его скрыли, иначе он просто уйдёт.';

create index if not exists suppliers_blocked_idx
  on public.suppliers (blocked_until)
  where blocked_until is not null;

-- ─────────────────────────── Политики чтения ───────────────────────────
--
-- Три исключения из скрытия, и каждое нужно:
--   1. сам владелец — иначе у него молча опустеет кабинет и он решит, что
--      приложение сломалось, вместо того чтобы прочитать причину;
--   2. администратор — иначе заблокированная компания исчезнет и из админки,
--      и снять блокировку станет нечем;
--   3. истёкший срок — блокировка «на две недели» должна сниматься сама,
--      без того чтобы кто-то помнил про неё через две недели.

drop policy if exists "read suppliers" on public.suppliers;
create policy "read suppliers" on public.suppliers
  for select using (
    blocked_until is null
    or blocked_until <= now()
    or owner_id = auth.uid()
    or exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'admin')
  );

-- Проверка блокировки обязана быть security definer, и это не перестраховка.
--
-- Сначала здесь стоял обычный подзапрос к suppliers прямо в политике offers.
-- Проверено на живой базе: не работает. Подзапрос к suppliers сам проходит
-- через политику «read suppliers», которая заблокированную компанию и
-- прячет, — строка не находится, not exists даёт true, и цены остаются
-- на виду. Компания исчезала (17 → 16), а её прайс висел в каталоге весь
-- (44 из 44). Функция читает таблицу мимо RLS и видит правду.
create or replace function public.supplier_blocked(p_supplier bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.suppliers s
     where s.id = p_supplier
       and s.blocked_until is not null
       and s.blocked_until > now()
  );
$$;

grant execute on function public.supplier_blocked(bigint) to anon, authenticated;

drop policy if exists "read offers" on public.offers;
create policy "read offers" on public.offers
  for select using (
    not public.supplier_blocked(offers.supplier_id)
    or offers.owner_id = auth.uid()
    or exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.role = 'admin')
  );

-- Карточки товаров намеренно НЕ скрываем. Товар — общая строка каталога,
-- на неё может ссылаться цена другой компании. Скрыв товар вместе с
-- поставщиком, мы убрали бы у остальных то, что им принадлежит.
-- Без цен карточка честно покажет «цена не указана».

-- ─────────────────────────── Действия админа ───────────────────────────

-- Заблокировать. p_days = null — бессрочно.
create or replace function public.admin_block_supplier(
  p_supplier bigint,
  p_days     int  default null,
  p_reason   text default null
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  until timestamptz;
begin
  perform public.admin_guard();

  if not exists (select 1 from public.suppliers where id = p_supplier) then
    raise exception 'Компания не найдена' using errcode = 'P0002';
  end if;

  until := case
             when p_days is null then 'infinity'::timestamptz
             else now() + make_interval(days => greatest(p_days, 1))
           end;

  update public.suppliers
     set blocked_until = until,
         blocked_at    = now(),
         block_reason  = nullif(btrim(coalesce(p_reason, '')), '')
   where id = p_supplier;

  return until;
end;
$$;

create or replace function public.admin_unblock_supplier(p_supplier bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_guard();
  update public.suppliers
     set blocked_until = null,
         blocked_at    = null,
         block_reason  = null
   where id = p_supplier;
end;
$$;

-- Удалить компанию.
--
-- Цены удаляем явно, хотя offers.supplier_id и так объявлен
-- ON DELETE CASCADE: так мы знаем их число и можем вернуть его админу.
-- Подтверждать удаление вслепую, не видя масштаба, — плохая идея.
--
-- Товары НЕ трогаем: карточка товара общая, на неё может ссылаться цена
-- другой компании. Убрав товар вместе с поставщиком, мы отняли бы у
-- остальных то, что принадлежит им. Карточка без цен честно скажет
-- «цена не указана».
--
-- Оплаты не трогаем: денежный след должен пережить удаление компании.
create or replace function public.admin_delete_supplier(p_supplier bigint)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  removed int;
begin
  perform public.admin_guard();

  if not exists (select 1 from public.suppliers where id = p_supplier) then
    raise exception 'Компания не найдена' using errcode = 'P0002';
  end if;

  delete from public.offers where supplier_id = p_supplier;
  get diagnostics removed = row_count;

  -- Профиль владельца остаётся: человек не перестаёт быть пользователем
  -- оттого, что его компанию убрали.
  --
  -- Роль возвращаем в 'buyer'. Именно 'buyer', а не 'user': в живой базе
  -- роли admin / buyer / designer / supplier, а проверки на колонке нет —
  -- выдуманное значение не вызвало бы ошибку, а тихо завело бы пятую роль,
  -- под которую не написана ни одна политика.
  --
  -- И только если человек был поставщиком: дизайнера, который завёл
  -- компанию, разжаловать в покупатели неправильно.
  update public.profiles
     set role = 'buyer', supplier_id = null
   where supplier_id = p_supplier and role = 'supplier';

  update public.profiles
     set supplier_id = null
   where supplier_id = p_supplier;

  delete from public.suppliers where id = p_supplier;

  return removed;
end;
$$;

revoke all on function public.admin_block_supplier(bigint,int,text) from anon;
revoke all on function public.admin_unblock_supplier(bigint)        from anon;
revoke all on function public.admin_delete_supplier(bigint)         from anon;

grant execute on function public.admin_block_supplier(bigint,int,text) to authenticated;
grant execute on function public.admin_unblock_supplier(bigint)        to authenticated;
grant execute on function public.admin_delete_supplier(bigint)         to authenticated;
