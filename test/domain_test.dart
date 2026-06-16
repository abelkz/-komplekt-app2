import 'package:flutter_test/flutter_test.dart';
import 'package:komplekt/features/catalog/domain/offer.dart';
import 'package:komplekt/features/catalog/domain/product.dart';
import 'package:komplekt/features/notifications/domain/price_drop.dart';
import 'package:komplekt/features/suppliers_map/domain/supplier.dart';

void main() {
  Product product(List<double> prices, {List<bool>? stock}) => Product(
        id: 'x',
        name: 'Товар',
        offers: [
          for (var i = 0; i < prices.length; i++)
            Offer(
              price: prices[i],
              inStock: stock == null ? true : stock[i],
              supplierId: 's$i',
              supplierName: 'Поставщик $i',
            ),
        ],
      );

  group('Product — вычисляемые поля', () {
    test('min/max цена и количество предложений', () {
      final p = product([4290, 4450, 5100]);
      expect(p.minPrice, 4290);
      expect(p.maxPrice, 5100);
      expect(p.offersCount, 3);
    });

    test('лучшее предложение — самое дешёвое', () {
      final p = product([8200, 7850]);
      expect(p.bestOffer!.price, 7850);
      expect(p.sortedOffers.first.price, 7850);
    });

    test('процент экономии', () {
      final p = product([4290, 5100]);
      // (1 - 4290/5100)*100 ≈ 15.88 → 16
      expect(p.savingPercent, 16);
    });

    test('без предложений — нули и null', () {
      const p = Product(id: 'x', name: 'Пусто');
      expect(p.minPrice, isNull);
      expect(p.savingPercent, 0);
      expect(p.bestOffer, isNull);
    });
  });

  group('PriceDrop.discountPercent', () {
    test('считает снижение', () {
      const d = PriceDrop(id: '1', oldPrice: 5000, newPrice: 4500);
      expect(d.discountPercent, 10);
    });
    test('ноль, если новая не ниже старой', () {
      const d = PriceDrop(id: '1', oldPrice: 5000, newPrice: 5000);
      expect(d.discountPercent, 0);
    });
  });

  group('Supplier.distanceLabel', () {
    test('метры и километры', () {
      const a = Supplier(id: '1', name: 'A', distanceM: 350);
      const b = Supplier(id: '2', name: 'B', distanceM: 1200);
      expect(a.distanceLabel, '350 м');
      expect(b.distanceLabel, '1.2 км');
    });
    test('null без расстояния', () {
      const a = Supplier(id: '1', name: 'A');
      expect(a.distanceLabel, isNull);
    });
  });
}
