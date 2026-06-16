import 'package:flutter_test/flutter_test.dart';
import 'package:komplekt/features/catalog/domain/offer.dart';
import 'package:komplekt/features/catalog/domain/product.dart';
import 'package:komplekt/features/catalog/presentation/catalog_providers.dart';

void main() {
  final products = [
    Product(id: 'a', name: 'A', offers: [
      const Offer(price: 4290, inStock: true, supplierId: 's1', city: 'Астана'),
      const Offer(price: 4690, inStock: false, supplierId: 's2', city: 'Алматы'),
    ]),
    Product(id: 'b', name: 'B', offers: [
      const Offer(price: 3150, inStock: true, supplierId: 's3', city: 'Алматы'),
    ]),
  ];

  test('фильтр по городу оставляет только предложения этого города', () {
    final res = applyFilters(
        products, const CatalogFilters(city: 'Астана'));
    expect(res.length, 1);
    expect(res.first.id, 'a');
    expect(res.first.offers.every((o) => o.city == 'Астана'), isTrue);
  });

  test('только в наличии убирает товары без stock-предложений', () {
    final res = applyFilters(
        products, const CatalogFilters(city: 'Алматы', inStock: true));
    expect(res.length, 1);
    expect(res.first.id, 'b'); // у A в Алматы предложение под заказ
  });

  test('сортировка по возрастанию цены', () {
    final res = applyFilters(products, const CatalogFilters());
    expect(res.first.id, 'b'); // 3150 < 4290
  });

  test('сортировка по убыванию цены', () {
    final res =
        applyFilters(products, const CatalogFilters(sort: SortBy.priceDesc));
    expect(res.first.id, 'a');
  });
}
