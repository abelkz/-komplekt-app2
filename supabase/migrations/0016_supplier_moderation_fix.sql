-- 0016 — заявка поставщика всегда уходит на проверку.
--
-- Раньше become_supplier() сохраняла статус, если он был 'approved'.
-- Задумка была «не понижать действующего поставщика», но у нового
-- клиента статус approved стоит по умолчанию — его никто не модерирует.
-- В итоге любой новый аккаунт получал кабинет мгновенно.

create or replace function public.become_supplier(
  p_company text,
  p_city    text default null,
  p_phone   text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me  uuid := auth.uid();
  row public.profiles;
begin
  if me is null then
    raise exception 'Нужно войти в аккаунт' using errcode = '28000';
  end if;
  if coalesce(btrim(p_company), '') = '' then
    raise exception 'Укажите название компании' using errcode = '22023';
  end if;

  update public.profiles p
     set company = btrim(p_company),
         city    = coalesce(nullif(btrim(p_city), ''), p.city),
         phone   = coalesce(nullif(btrim(p_phone), ''), p.phone),
         role    = case when p.role = 'admin' then p.role else 'supplier' end,
         status  = case
                     when p.role = 'admin' then p.status
                     -- одобренным считаем только того, кто УЖЕ был поставщиком
                     when p.role = 'supplier' and p.status = 'approved' then 'approved'
                     else 'pending'
                   end
   where p.id = me
  returning p.* into row;

  if not found then
    raise exception 'Профиль не найден' using errcode = 'P0002';
  end if;

  return row;
end;
$fn$;
