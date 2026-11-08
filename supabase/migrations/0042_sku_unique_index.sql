-- ============================================================
-- КОМПЛЕКТ · 0042 — защитный индекс по артикулу
--
-- Применять ПОСЛЕДНИМ: только после того, как дубли разобраны во
-- вкладке «Дубли» админки. Пока дубли есть, индекс не создастся —
-- и это правильно: он для того и нужен, чтобы новых не появлялось.
--
-- Почему отдельным файлом, а не в 0040. В 0013 такой индекс
-- создавался внутри do-блока, который глотал unique_violation и
-- печатал notice. При существующих дублях он молча не создавался,
-- в живой базе его, скорее всего, нет, и защиты не было — а по
-- миграции выглядело, будто есть. Здесь отказ виден сразу.
--
-- Старый индекс products_brand_sku_uniq (по upper(sku)) не мешает:
-- он слабее нового, потому что не убирает дефисы и пробелы.
-- Удалять его незачем, он просто перестаёт быть единственным.
-- ============================================================

do $$
declare
  groups int;
  sample text;
begin
  select count(*), string_agg(t.k, ', ')
    into groups, sample
    from (select coalesce(brand_id, -1)::text || '/' || sku_norm as k
            from public.products
           where sku_norm is not null
           group by coalesce(brand_id, -1), sku_norm
          having count(*) > 1
           limit 10) t;

  if groups > 0 then
    raise exception
      'Индекс не создан: есть карточки с одинаковым артикулом (% групп, например %). Разберите их во вкладке «Дубли» админки и примените файл заново',
      groups, sample
      using errcode = '23505';
  end if;
end $$;

create unique index if not exists products_brand_sku_norm_uniq
  on public.products (coalesce(brand_id, -1), sku_norm)
  where sku_norm is not null;

comment on index public.products_brand_sku_norm_uniq is
  'Один заводской артикул в пределах марки — одна карточка каталога';
