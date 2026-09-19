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

  test('потолок цены режет предложения, а не только карточки', () {
    final res = applyFilters(products, const CatalogFilters(maxPrice: 4300));
    expect(res.length, 2);
    final a = res.firstWhere((p) => p.id == 'a');
    // 4690 дороже потолка — этой строки в карточке остаться не должно
    expect(a.offers.length, 1);
    expect(a.offers.first.price, 4290);
  });

  test('потолок ниже всех цен оставляет пустой список', () {
    expect(applyFilters(products, const CatalogFilters(maxPrice: 1000)), isEmpty);
  });

  test('фильтр по марке отсекает товар целиком', () {
    final withBrands = [
      const Product(id: 'c', name: 'C', brand: 'Cersanit', offers: [
        Offer(price: 5000, inStock: true, supplierId: 's4', city: 'Астана'),
      ]),
      const Product(id: 'd', name: 'D', brand: 'Kerama Marazzi', offers: [
        Offer(price: 6000, inStock: true, supplierId: 's5', city: 'Астана'),
      ]),
    ];
    final res =
        applyFilters(withBrands, const CatalogFilters(brand: 'Cersanit'));
    expect(res.length, 1);
    expect(res.first.id, 'c');
  });

  test('фильтры не теряют поля товара при пересборке', () {
    final rich = [
      const Product(
        id: 'e',
        name: 'E',
        packQty: 1.44,
        warrantyMonths: 60,
        attrs: ['R10'],
        offers: [
          Offer(price: 100, inStock: true, supplierId: 's6', city: 'Астана'),
        ],
      ),
    ];
    final res = applyFilters(rich, const CatalogFilters());
    expect(res.first.packQty, 1.44);
    expect(res.first.warrantyMonths, 60);
    expect(res.first.attrs, ['R10']);
  });

  test('copyWith сбрасывает необязательные фильтры только по флагу', () {
    const f = CatalogFilters(maxPrice: 5000, brand: 'Cersanit');
    expect(f.copyWith(inStock: true).maxPrice, 5000);
    expect(f.copyWith(clearMaxPrice: true).maxPrice, isNull);
    expect(f.copyWith(clearMaxPrice: true).brand, 'Cersanit');
    expect(f.copyWith(clearBrand: true).brand, isNull);
  });

  test('чипы марок молчат, пока марка одна', () {
    expect(brandsOf(products), isEmpty);
    expect(
      brandsOf([
        const Product(id: 'c', name: 'C', brand: 'Cersanit'),
        const Product(id: 'd', name: 'D', brand: 'Kerama Marazzi'),
      ]),
      ['Cersanit', 'Kerama Marazzi'],
    );
  });

  test('счётчик наличия считает товары, а не предложения', () {
    // У «a» два предложения, в наличии одно — товар всё равно один
    expect(inStockCountOf(products), 2);
    expect(
      inStockCountOf([
        const Product(id: 'z', name: 'Z', offers: [
          Offer(price: 1, inStock: false, supplierId: 's', city: 'Астана'),
        ]),
      ]),
      0,
    );
  });
}
