import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../../catalog/domain/product.dart';

/// Избранное пользователя.
class FavoritesRepository {
  const FavoritesRepository();

  String? get _uid => supabase.auth.currentUser?.id;

  /// Множество id избранных товаров (для подсветки сердечек).
  Future<Set<String>> ids() async {
    final uid = _uid;
    if (uid == null) return {};
    try {
      final rows = await supabase
          .from('favorites')
          .select('product_id')
          .eq('user_id', uid);
      return rows.map<String>((m) => m['product_id'].toString()).toSet();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить избранное');
    }
  }

  /// Избранные товары целиком (с ценами/фото) — для экрана «Избранное».
  Future<List<Product>> products() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await supabase.from('favorites').select(
            'products(id,name,sku,unit,color,rating,category_slug,brand,'
            'product_images(url,sort),'
            'offers(id,price,in_stock,price_updated_at,supplier_id,'
            'suppliers(name,city,phone,whatsapp,website)))',
          ).eq('user_id', uid);
      return rows
          .map((m) => m['products'])
          .whereType<Map<String, dynamic>>()
          .map<Product>(Product.fromMap)
          .toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить избранное');
    }
  }

  Future<void> add(String productId) async {
    final uid = _uid;
    if (uid == null) throw const Failure('Войдите, чтобы сохранять избранное');
    try {
      await supabase
          .from('favorites')
          .upsert({'user_id': uid, 'product_id': productId});
    } catch (e) {
      throw mapError(e, fallback: 'Не сохранилось');
    }
  }

  Future<void> remove(String productId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await supabase
          .from('favorites')
          .delete()
          .eq('user_id', uid)
          .eq('product_id', productId);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось убрать из избранного');
    }
  }
}
