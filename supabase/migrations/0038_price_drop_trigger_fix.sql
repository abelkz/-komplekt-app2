-- ============================================================
-- КОМПЛЕКТ · 0038 — триггер снижения цены: приводим репозиторий к живой базе
--
-- Что было не так. В репозитории лежит функция `on_offer_price_drop`
-- (миграция 0006), которая читает `public.users`. Такой таблицы в живой
-- базе НЕТ (CLAUDE.md §6.1) — то есть при развёртывании с нуля триггер
-- либо не создался бы, либо падал на каждом изменении цены.
--
-- А в живой базе всё это время работает ДРУГАЯ функция —
-- `offers_notify_price_drop`: её переписали прямо в SQL Editor под
-- реальную схему (читает `profiles`), и в репозиторий правка не попала.
-- Ровно та же история, что была с `delete_my_account` (см. 0026 и
-- CLAUDE.md §10.1). Текст снят с живой базы 19.09.2026 через
-- pg_get_functiondef.
--
-- ОДНА НАМЕРЕННАЯ ПРАВКА против живой версии: строки вставляются со
-- статусом 'pending', а не 'sent'. В живой версии стоит 'sent' — то есть
-- строка помечена отправленной ДО того, как что-либо отправлено. Из-за
-- этого запасной путь в send-price-alerts (он выбирает `status = 'pending'`,
-- см. index.ts) не находит ничего и никогда. Пока доставка идёт через
-- Database Webhook, это незаметно: функция берёт запись прямо из вызова.
-- Но если вебхук однажды не сработает, уведомления теряются молча и
-- восстановить их нечем. Статус 'sent' функция проставит сама после
-- реальной отправки.
--
-- Старую `on_offer_price_drop` не удаляем: в живой базе её и так нет,
-- а на чужих развёртываниях она может быть привязана к своему триггеру.
-- ============================================================

create or replace function public.offers_notify_price_drop()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  d      numeric;
  p_name text;
  s_name text;
begin
  -- Только снижение. Повышение цены и первая установка (null) молчат.
  if old.price is null or new.price is null or new.price >= old.price then
    return null;
  end if;

  d := round((1 - new.price / old.price) * 100);

  select p.name into p_name from public.products  p where p.id = new.product_id;
  select s.name into s_name from public.suppliers s where s.id = new.supplier_id;

  -- Имя товара и поставщика кладём в строку сразу: пуш уходит позже,
  -- и к тому моменту товар могли переименовать или снять с продажи.
  insert into public.price_drops
    (user_id, product_id, product_name, supplier_name, old_price, new_price, status)
  select f.user_id,
         new.product_id,
         coalesce(p_name, 'Товар'),
         coalesce(s_name, ''),
         old.price,
         new.price,
         'pending'
  from public.favorites f
  left join public.profiles pr on pr.id = f.user_id
  where f.product_id = new.product_id
    and f.user_id is not null
    -- left join и coalesce нарочно: у человека может не быть строки
    -- в profiles, и терять из-за этого уведомление неправильно.
    and coalesce(pr.notify_price_drops, true)
    and d >= coalesce(pr.notify_threshold, 10);

  return null;
end;
$$;

drop trigger if exists offers_notify_price_drop on public.offers;

create trigger offers_notify_price_drop
  after update of price on public.offers
  for each row
  execute function public.offers_notify_price_drop();
