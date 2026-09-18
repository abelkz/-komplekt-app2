-- ============================================================================
-- 0026. Удаление аккаунта: фиксация версии, которая реально работает.
--
-- Откуда взялось: функцию чинили SQL-ом прямо в дашборде, минуя репозиторий
-- (после коммита 0e84670, который только показывал настоящую ошибку вместо
-- «что-то пошло не так»). В миграциях оставалась версия из 0006_hardening.sql
-- в одну строку — `delete from auth.users`, — и при разворачивании базы с нуля
-- удаление аккаунта сломалось бы снова.
--
-- Текст ниже снят с живой базы 18.09.2026 через pg_get_functiondef и
-- переформатирован для читаемости; логика не менялась.
--
-- Почему в 0006 не работало: у auth.users есть дочерние строки в public.*,
-- и не у всех внешний ключ объявлен с on delete cascade. Удаление падало на
-- нарушении ссылочной целостности, а пользователь видел ошибку.
--
-- Скрипт идемпотентный: повторный запуск безопасен.
-- ============================================================================

create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
declare
  uid  uuid := auth.uid();
  r    record;
  pass int;
begin
  if uid is null then
    raise exception 'Не авторизован';
  end if;

  -- Несколько проходов: за счёт повторов удаляются и дочерние, и родительские
  -- строки. Порядок таблиц заранее неизвестен, поэтому вместо того чтобы его
  -- вычислять, просто повторяем — то, что в первый проход мешал внешний ключ,
  -- уйдёт во второй или третий.
  for pass in 1..6 loop
    for r in
      select table_name, column_name
        from information_schema.columns
       where table_schema = 'public'
         and column_name in ('user_id', 'owner_id')
    loop
      begin
        execute format('delete from public.%I where %I = $1',
                       r.table_name, r.column_name) using uid;
      exception when others then
        null;  -- связь мешает — удалится на следующем проходе
      end;
    end loop;
  end loop;

  -- Профиль и users отдельно: там идентификатор лежит в id, а не в user_id.
  -- Обёрнуто в begin/exception, потому что public.users в живой базе нет
  -- (см. CLAUDE.md §6.1), а в развёрнутой с нуля — есть.
  begin
    execute 'delete from public.profiles where id = $1' using uid;
  exception when others then
    null;
  end;

  begin
    execute 'delete from public.users where id = $1' using uid;
  exception when others then
    null;
  end;

  -- Сам аккаунт — последним, когда ссылаться на него уже некому.
  delete from auth.users where id = uid;
end;
$$;

comment on function public.delete_my_account() is
  'Удаление аккаунта (требование App Store 5.1.1(v) и закона РК). Чистит '
  'public.* в несколько проходов, потому что не у всех ссылок на auth.users '
  'объявлен on delete cascade; версия снята с живой базы 18.09.2026';
