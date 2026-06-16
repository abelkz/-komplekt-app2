import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../../catalog/domain/product.dart';
import '../domain/supplier.dart';

/// Поставщики: поиск рядом (PostGIS RPC), карточка, витрина товаров.
class SupplierRepository {
  const SupplierRepository();

  /// Поставщики рядом — сортировка по расстоянию (функция nearby_suppliers).
  Future<List<Supplier>> nearby({
    required double lat,
    required double lng,
    double radiusM = 30000,
  }) async {
    try {
      final rows = await supabase.rpc('nearby_suppliers', params: {
        'p_lat': lat,
        'p_lng': lng,
        'p_radius_m': radiusM,
      });
      return (rows as List)
          .map<Supplier>((m) => Supplier.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось найти поставщиков рядом');
    }
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
            'products(id,name,sku,unit,color,rating,category_slug,brand,'
            'product_images(url,sort))',
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
