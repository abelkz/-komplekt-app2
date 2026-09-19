import 'package:flutter_test/flutter_test.dart';
import 'package:komplekt/features/collections/presentation/widgets/qty_calculator_page.dart';

/// Расчёт расхода — единственное место, где приложение считает деньги
/// заказчика вперёд. Ошибка здесь видна только на объекте, поэтому
/// поведение зафиксировано тестами.
void main() {
  test('запас на подрезку добавляется к введённому количеству', () {
    const c = QtyCalc(base: 38, sparePercent: 10, unit: 'м²');
    expect(c.withSpare, closeTo(41.8, 0.001));
  });

  test('без запаса итог равен введённому', () {
    const c = QtyCalc(base: 38, sparePercent: 0, unit: 'м²');
    expect(c.total, 38);
  });

  test('округление идёт вверх до целых упаковок', () {
    // 38 м² + 10 % = 41.8 → 30 коробок по 1.44 = 43.2 м²
    const c =
        QtyCalc(base: 38, sparePercent: 10, packQty: 1.44, unit: 'м²');
    expect(c.packs, 30);
    expect(c.total, closeTo(43.2, 0.001));
  });

  test('ровно укладывающееся количество не даёт лишней упаковки', () {
    // 14.4 м² ровно 10 коробок — одиннадцатая не нужна
    const c = QtyCalc(base: 14.4, sparePercent: 0, packQty: 1.44, unit: 'м²');
    expect(c.packs, 10);
    expect(c.total, closeTo(14.4, 0.001));
  });

  test('нулевая фасовка трактуется как её отсутствие', () {
    const c = QtyCalc(base: 10, sparePercent: 0, packQty: 0, unit: 'м²');
    expect(c.pack, isNull);
    expect(c.packs, isNull);
    expect(c.total, 10);
  });

  test('штучный товар округляется вверх до целой штуки', () {
    // 7 шт + 10 % = 7.7 → 8 штук: 0.7 розетки не продадут
    const c = QtyCalc(base: 7, sparePercent: 10);
    expect(c.total, 8);
  });

  test('погонные метры дробными остаются', () {
    const c = QtyCalc(base: 7, sparePercent: 10, unit: 'м');
    expect(c.total, closeTo(7.7, 0.001));
  });
}
