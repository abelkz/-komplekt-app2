import 'package:flutter_test/flutter_test.dart';
import 'package:komplekt/features/supplier_cabinet/data/sku_match.dart';

/// Склейка карточек каталога держится на этой нормализации: если она
/// разойдётся с уникальным индексом `products_brand_sku_uniq` (он по
/// `upper(sku)`), импорт прайса снова начнёт плодить дубли и падать.
void main() {
  group('normSku', () {
    test('регистр и разделители не важны — это один артикул', () {
      const expected = 'DD640200R';
      expect(normSku('DD640200R'), expected);
      expect(normSku('dd640200r'), expected);
      expect(normSku('DD-640200 R'), expected);
      expect(normSku('  dd/640200_r  '), expected);
      expect(normSku('DD.640200.R'), expected);
    });

    test('кириллица сохраняется — артикулы местных заводов', () {
      expect(normSku('цем-м400'), 'ЦЕММ400');
      expect(normSku('ЦЕМ М400'), 'ЦЕММ400');
    });

    test('разные артикулы не склеиваются', () {
      expect(normSku('DD640200R') == normSku('DD640201R'), isFalse);
    });

    test('пусто и мусор дают null — склеивать не с чем', () {
      expect(normSku(null), isNull);
      expect(normSku(''), isNull);
      expect(normSku('   '), isNull);
      expect(normSku('---'), isNull);
    });
  });

  group('skuLookupVariants', () {
    test('ищем все написания, которые встречаются в прайсах', () {
      final v = skuLookupVariants('DD-640200 r');
      expect(v, contains('DD-640200 r')); // как в прайсе
      expect(v, contains('DD-640200 R')); // верхний регистр
      expect(v, contains('dd-640200 r')); // нижний
      expect(v, contains('DD640200R')); // без разделителей
      expect(v.toSet().length, v.length, reason: 'без повторов');
    });

    test('пустой артикул — искать нечего', () {
      expect(skuLookupVariants(null), isEmpty);
      expect(skuLookupVariants('  '), isEmpty);
    });
  });

  group('normName', () {
    test('лишние пробелы и регистр не делают товар другим', () {
      expect(normName('  Цемент   М400  50 кг '), 'ЦЕМЕНТ М400 50 КГ');
      expect(normName('цемент м400 50 кг'), 'ЦЕМЕНТ М400 50 КГ');
    });
  });

  group('chunked', () {
    test('делит на пачки, последняя — неполная', () {
      expect(chunked([1, 2, 3, 4, 5], 2).toList(), [
        [1, 2],
        [3, 4],
        [5],
      ]);
    });

    test('короткий список — одна пачка, пустой — ни одной', () {
      expect(chunked([1, 2], 10).toList(), [
        [1, 2]
      ]);
      expect(chunked(<int>[], 10).toList(), isEmpty);
    });

    test('ничего не теряется и порядок сохраняется', () {
      final src = List.generate(205, (i) => i);
      final flat = chunked(src, 100).expand((e) => e).toList();
      expect(flat, src);
    });
  });
}
