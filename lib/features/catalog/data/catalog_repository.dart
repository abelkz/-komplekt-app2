import 'package:supabase_flutter/supabase_flutter.dart' show TextSearchType;

import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/category.dart';
import '../domain/product.dart';

/// Доступ к каталогу: категории, товары, поиск, карточка товара.
class CatalogRepository {
  const CatalogRepository();

  // Поля товара с вложенными фото и предложениями (с именем поставщика).
  // ВАЖНО: без пробелов/переносов — PostgREST требует компактную строку.
  static const _productSelect =
      'id,name,sku,unit,color,description,rating,category_slug,brand,'
      'product_images(url,sort),'
      'offers(id,price,in_stock,price_updated_at,supplier_id,'
      'suppliers(name,city,phone,whatsapp,website))';

  /// Список категорий (по полю sort).
  Future<List<Category>> categories() async {
    try {
      final rows = await supabase
          .from('categories')
          .select('slug,name,icon,sort')
          .order('sort');
      return rows.map<Category>((m) => Category.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить категории');
    }
  }

  /// Товары по категории.
  Future<List<Product>> byCategory(String slug) async {
    try {
      final rows = await supabase
          .from('products')
          .select(_productSelect)
          .eq('category_slug', slug)
          .order('id');
      return rows.map<Product>((m) => Product.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить товары');
    }
  }

  /// Поиск: сначала полнотекстовый (русский, ранжирование), затем —
  /// fallback на ILIKE (короткие запросы, опечатки, артикулы).
  Future<List<Product>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final rows = await supabase
          .from('products')
          .select(_productSelect)
          .textSearch('search_tsv', q,
              config: 'russian', type: TextSearchType.websearch)
          .limit(100);
      if (rows.isNotEmpty) {
        return rows.map<Product>((m) => Product.fromMap(m)).toList();
      }
      return _searchIlike(q); // ничего не нашлось — пробуем по подстроке
    } catch (_) {
      // search_tsv ещё нет (миграция не прогнана) или иная ошибка
      return _searchIlike(q);
    }
  }

  Future<List<Product>> _searchIlike(String q) async {
    try {
      final rows = await supabase
          .from('products')
          .select(_productSelect)
          .or('name.ilike.%$q%,sku.ilike.%$q%,brand.ilike.%$q%')
          .limit(100);
      return rows.map<Product>((m) => Product.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Поиск не удался');
    }
  }

  /// Лента «вдохновения» для главной с пагинацией (range).
  Future<List<Product>> feed({int limit = 20, int offset = 0}) async {
    try {
      final rows = await supabase
          .from('products')
          .select(_productSelect)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map<Product>((m) => Product.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить ленту');
    }
  }

  /// Одна карточка товара по id.
  Future<Product> byId(String id) async {
    try {
      final row = await supabase
          .from('products')
          .select(_productSelect)
          .eq('id', id)
          .maybeSingle();
      if (row == null) throw const Failure('Товар не найден');
      return Product.fromMap(row);
    } catch (e) {
      if (e is Failure) rethrow;
      throw mapError(e, fallback: 'Не удалось открыть товар');
    }
  }
}
