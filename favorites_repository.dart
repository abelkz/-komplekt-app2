import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../../catalog/data/catalog_repository.dart';
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
  /// Набор полей берём из каталога: в живой базе нет колонки products.brand,
  /// марка приезжает вложенным объектом brands(name).
  Future<List<Product>> products() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await supabase
          .from('favorites')
          .select('products(${CatalogRepository.productSelect})')
          .eq('user_id', uid);
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
          .insert({'user_id': uid, 'product_id': productId});
    } on PostgrestException catch (e) {
      // 23505 — товар уже в избранном, это не ошибка для пользователя
      if (e.code == '23505') return;
      throw mapError(e, fallback: 'Не сохранилось');
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
