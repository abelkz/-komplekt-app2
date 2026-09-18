-- ============================================================================
-- 0027. «Подешевело за неделю» — реальное падение цены за период.
--
-- Зачем: на главной была секция, отсортированная по savingPercent — это
-- разброс между самым дешёвым и самым дорогим предложением на один товар,
-- то есть «где переплачивают», а не «где подешевело». Настоящее падение
-- цены лежит в price_history, но напрямую из приложения её не прочитать.
--
-- Почему функция, а не запрос: price_history закрыта политиками (0018) —
-- её видит владелец предложения и пользователь с активным тарифом Про.
-- Главную же смотрит и гость. Функция с security definer отдаёт только
-- агрегат: на сколько упала минимальная цена товара. Кто именно и когда
-- менял цену — по-прежнему за тарифом, здесь этого нет.
--
-- Типы (bigint) взяты из 0018_price_history_table.sql, где price_history
-- ссылается на products(id) и offers(id) — в живой базе ключи целочисленные
-- (см. CLAUDE.md §6.1).
--
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

create or replace function public.price_drops(
  p_days  int default 7,
  p_limit int default 20
)
returns table (
  product_id bigint,
  old_price  numeric,
  new_price  numeric,
  pct        int
)
language sql
security definer
set search_path = public
stable
as $$
  with cutoff as (
    select now() - make_interval(days => greatest(p_days, 1)) as ts
  ),
  per_offer as (
    select
      o.product_id,
      o.price as new_price,
      -- Цена на начало периода: последняя запись до отсечки. Если предложение
      -- появилось внутри периода — берём самую раннюю известную. Если истории
      -- нет вовсе, считаем, что цена не менялась.
      coalesce(
        (select h.price
           from public.price_history h, cutoff
          where h.offer_id = o.id
            and h.changed_at <= cutoff.ts
          order by h.changed_at desc
          limit 1),
        (select h.price
           from public.price_history h
          where h.offer_id = o.id
          order by h.changed_at asc
          limit 1),
        o.price
      ) as old_price
    from public.offers o
  ),
  per_product as (
    select product_id,
           min(new_price) as new_min,
           min(old_price) as old_min
      from per_offer
     group by product_id
  )
  select product_id,
         old_min,
         new_min,
         round((1 - new_min / old_min) * 100)::int
    from per_product
   where old_min > 0
     and new_min < old_min
     -- Округление до процента: «−0,4 %» никому не интересно и выглядит
     -- как шум, а не как повод открыть товар.
     and round((1 - new_min / old_min) * 100) >= 1
   order by round((1 - new_min / old_min) * 100) desc, product_id
   limit greatest(p_limit, 1);
$$;

revoke all on function public.price_drops(int, int) from public;
grant execute on function public.price_drops(int, int) to anon, authenticated;

comment on function public.price_drops(int, int) is
  'Товары, у которых минимальная цена упала за N дней. Агрегат поверх '
  'price_history: саму историю (кто и когда менял цену) функция не отдаёт — '
  'та остаётся за тарифом Про';
