import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../../catalog/domain/product.dart';
import '../../suppliers_map/domain/supplier.dart';

/// Импортируемая строка прайса (после сопоставления колонок).
class PriceRow {
  PriceRow({
    required this.name,
    required this.price,
    this.sku,
    this.unit = 'шт',
    this.imageUrl,
  });
  final String name;
  final double price;
  final String? sku;
  final String unit;
  final String? imageUrl;
}

/// Статистика по товару (просмотры/контакты).
class ProductStat {
  const ProductStat(this.views, this.contacts);
  final int views;
  final int contacts;
}

/// Кабинет поставщика: компания, товары, цены, импорт, статистика.
class SupplierCabinetRepository {
  const SupplierCabinetRepository();

  String? get _uid => supabase.auth.currentUser?.id;

  /// Найти карточку компании владельца или создать её.
  Future<Supplier> ensureCompany({
    required String fallbackName,
    required String city,
    String? phone,
  }) async {
    final uid = _uid;
    if (uid == null) throw const Failure('Нужно войти');
    try {
      final existing = await supabase
          .from('suppliers')
          .select()
          .eq('owner_id', uid)
          .limit(1)
          .maybeSingle();
      if (existing != null) return Supplier.fromMap(existing);

      final created = await supabase
          .from('suppliers')
          .insert({
            'owner_id': uid,
            'name': fallbackName.isEmpty ? 'Моя компания' : fallbackName,
            'city': city,
            'phone': phone,
          })
          .select()
          .single();
      return Supplier.fromMap(created);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось создать карточку компании');
    }
  }

  /// Мои товары (созданные мной) с моей ценой и фото.
  Future<List<Product>> myProducts() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await supabase
          .from('products')
          .select('id,name,sku,unit,color,category_slug,brand,'
              'product_images(url,sort),'
              'offers(id,price,in_stock,price_updated_at,supplier_id)')
          .eq('created_by', uid)
          .order('created_at', ascending: false);
      return rows.map<Product>((m) => Product.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить товары');
    }
  }

  /// Добавить один товар (+ цену + фото при наличии ссылки).
  Future<void> addProduct({
    required String name,
    required String categorySlug,
    required String unit,
    required double price,
    required bool inStock,
    required String supplierId,
    String? sku,
    String? imageUrl,
  }) async {
    final uid = _uid;
    if (uid == null) throw const Failure('Нужно войти');
    try {
      final product = await supabase
          .from('products')
          .insert({
            'name': name,
            'sku': sku,
            'unit': unit,
            'category_slug': categorySlug,
            'created_by': uid,
          })
          .select('id')
          .single();
      final productId = product['id'];

      await supabase.from('offers').insert({
        'product_id': productId,
        'supplier_id': supplierId,
        'owner_id': uid,
        'price': price,
        'in_stock': inStock,
      });

      if (imageUrl != null && imageUrl.isNotEmpty) {
        await supabase
            .from('product_images')
            .insert({'product_id': productId, 'url': imageUrl, 'sort': 0});
      }
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось сохранить товар');
    }
  }

  /// Обновить цену/наличие. Если предложения ещё нет — создаём.
  Future<void> saveOffer({
    String? offerId,
    required String productId,
    required String supplierId,
    required double price,
    required bool inStock,
  }) async {
    final uid = _uid;
    if (uid == null) throw const Failure('Нужно войти');
    try {
      if (offerId == null) {
        await supabase.from('offers').insert({
          'product_id': productId,
          'supplier_id': supplierId,
          'owner_id': uid,
          'price': price,
          'in_stock': inStock,
        });
      } else {
        await supabase.from('offers').update({
          'price': price,
          'in_stock': inStock,
          'price_updated_at': DateTime.now().toIso8601String(),
        }).eq('id', offerId);
      }
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось сохранить цену');
    }
  }

  Future<void> deleteProduct(String productId) async {
    try {
      await supabase.from('products').delete().eq('id', productId);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось удалить товар');
    }
  }

  /// Массовый импорт прайса: товары + цены одной пачкой.
  /// Возвращает количество загруженных позиций.
  Future<int> importPrice({
    required List<PriceRow> rows,
    required String categorySlug,
    required String supplierId,
  }) async {
    final uid = _uid;
    if (uid == null) throw const Failure('Нужно войти');
    if (rows.isEmpty) return 0;
    try {
      // 1) товары пачкой
      final productsPayload = rows
          .map((r) => {
                'name': r.name,
                'sku': r.sku,
                'unit': r.unit,
                'category_slug': categorySlug,
                'created_by': uid,
              })
          .toList();
      final inserted = await supabase
          .from('products')
          .insert(productsPayload)
          .select('id');

      // 2) к каждому — цена (порядок сохраняется)
      final offersPayload = <Map<String, dynamic>>[];
      final imagesPayload = <Map<String, dynamic>>[];
      for (var i = 0; i < inserted.length; i++) {
        final pid = inserted[i]['id'];
        offersPayload.add({
          'product_id': pid,
          'supplier_id': supplierId,
          'owner_id': uid,
          'price': rows[i].price,
          'in_stock': true,
        });
        final img = rows[i].imageUrl;
        if (img != null && img.isNotEmpty) {
          imagesPayload.add({'product_id': pid, 'url': img, 'sort': 0});
        }
      }
      await supabase.from('offers').insert(offersPayload);
      if (imagesPayload.isNotEmpty) {
        await supabase.from('product_images').insert(imagesPayload);
      }
      return inserted.length;
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить прайс');
    }
  }

  /// Статистика просмотров/контактов по моим товарам.
  Future<Map<String, ProductStat>> stats(String supplierId) async {
    try {
      final rows =
          await supabase.rpc('supplier_stats', params: {'p_supplier': supplierId});
      final map = <String, ProductStat>{};
      for (final r in (rows as List)) {
        final m = r as Map<String, dynamic>;
        map[m['product_id'].toString()] = ProductStat(
          (m['views'] as num?)?.toInt() ?? 0,
          (m['contacts'] as num?)?.toInt() ?? 0,
        );
      }
      return map;
    } catch (e) {
      // статистика не критична — возвращаем пусто
      return {};
    }
  }

  /// Стать поставщиком (меняет роль текущего пользователя на supplier/pending).
  Future<void> becomeSupplier() async {
    try {
      await supabase.rpc('become_supplier');
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось оформить заявку');
    }
  }
}
