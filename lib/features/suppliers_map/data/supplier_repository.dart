import 'dart:math' as math;

import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../../catalog/domain/product.dart';
import '../domain/supplier.dart';

/// Поставщики: поиск рядом, карточка, витрина товаров.
class SupplierRepository {
  const SupplierRepository();

  /// Поставщики с указанными координатами, отсортированные по расстоянию
  /// до пользователя. Расстояние считаем в приложении (формула гаверсинуса),
  /// без PostGIS: точек немного, а зависимости и права на расширение это
  /// не требует.
  Future<List<Supplier>> nearby({
    required double lat,
    required double lng,
  }) async {
    try {
      final rows = await supabase
          .from('suppliers')
          .select()
          .not('lat', 'is', null)
          .not('lng', 'is', null);

      final list = rows
          .map<Supplier>((m) => Supplier.fromMap(m))
          .where((s) => s.hasLocation)
          .map((s) => s.copyWith(
              distanceM: _distanceM(lat, lng, s.lat!, s.lng!)))
          .toList()
        ..sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
      return list;
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось найти поставщиков');
    }
  }

  /// Расстояние между двумя точками в метрах (формула гаверсинуса).
  static double _distanceM(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // радиус Земли, м
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Все поставщики города (запасной вариант, если нет геолокации).
  Future<List<Supplier>> byCity(String city) async {
    try {
      final rows = await supabase
          .from('suppliers')
          .select()
          .eq('city', city)
          .order('rating', ascending: false);
      return rows.map<Supplier>((m) => Supplier.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить поставщиков');
    }
  }

  Future<Supplier> byId(String id) async {
    try {
      final row =
          await supabase.from('suppliers').select().eq('id', id).maybeSingle();
      if (row == null) throw const Failure('Поставщик не найден');
      return Supplier.fromMap(row);
    } catch (e) {
      if (e is Failure) rethrow;
      throw mapError(e, fallback: 'Не удалось открыть поставщика');
    }
  }

  /// Витрина продавца: товары, на которые у него есть предложения.
  Future<List<Product>> products(String supplierId) async {
    try {
      final rows = await supabase
          .from('offers')
          .select(
            'price,in_stock,price_updated_at,supplier_id,'
            'products(id,name,sku,unit,color,rating,category_slug,brand_id,'
            'brands(name),product_images(url,sort))',
          )
          .eq('supplier_id', supplierId);

      // Превращаем строки offers -> товары с одним (этим) предложением.
      final result = <Product>[];
      for (final row in rows) {
        final p = row['products'];
        if (p is! Map<String, dynamic>) continue;
        final merged = {
          ...p,
          'offers': [
            {
              'price': row['price'],
              'in_stock': row['in_stock'],
              'price_updated_at': row['price_updated_at'],
              'supplier_id': row['supplier_id'],
            }
          ],
        };
        result.add(Product.fromMap(merged));
      }
      return result;
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить товары продавца');
    }
  }
}
