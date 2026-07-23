import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/category.dart';
import '../domain/product.dart';

/// Доступ к каталогу: категории, товары, поиск, карточка товара.
class CatalogRepository {
  const CatalogRepository();

  // Поля товара с вложенными фото и предложениями (с именем поставщика).
  // ВАЖНО: без пробелов/переносов — PostgREST требует компактную строку.
  //
  // В живой базе НЕТ колонки products.brand — марка лежит в отдельной
  // таблице brands и приезжает вложенным объектом brands(name).
  // Запрашивать несуществующую колонку нельзя: PostgREST отвечает 42703
  // и падает весь запрос (из-за этого «Поиск не удался» и пустое избранное).
  static const productSelect =
      'id,name,sku,unit,color,image_url,description,rating,category_slug,'
      'brand_id,'
      'brands(name),'
      'product_images(url,sort),'
      'offers(id,price,prev_price,in_stock,price_updated_at,supplier_id,'
      'suppliers(name,city,phone,whatsapp,website))';

  /// Список категорий (по полю sort).
  /// Колонку с иконкой не перечисляем явно: в живой базе она называется
  /// `emoji`, в схеме Flutter-миграций — `icon`. Забираем всё и разбираем
  /// в Category.fromMap.
  Future<List<Category>> categories() async {
    try {
      final rows = await supabase.from('categories').select().order('sort');
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
          .select(productSelect)
          .eq('category_slug', slug)
          .order('id');
      return rows.map<Product>((m) => Product.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить товары');
    }
  }

  /// Поиск по названию, артикулу и марке.
  ///
  /// Марка хранится в отдельной таблице, поэтому сначала ищем подходящие
  /// бренды, а потом добавляем их id в общий фильтр — так «Керама» находит
  /// товары Kerama Marazzi, а «керамо» — керамогранит по названию.
  Future<List<Product>> search(String query) async {
    final q = _sanitize(query);
    if (q.isEmpty) return [];
    try {
      final filters = <String>['name.ilike.%$q%', 'sku.ilike.%$q%'];
      final brandIds = await _brandIds(q);
      if (brandIds.isNotEmpty) {
        filters.add('brand_id.in.(${brandIds.join(',')})');
      }
      final rows = await supabase
          .from('products')
          .select(productSelect)
          .or(filters.join(','))
          .limit(100);
      return rows.map<Product>((m) => Product.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Поиск не удался');
    }
  }

  /// id марок, чьё название похоже на запрос. Ошибку не поднимаем:
  /// поиск по названию товара должен работать в любом случае.
  Future<List<String>> _brandIds(String q) async {
    try {
      final rows =
          await supabase.from('brands').select('id').ilike('name', '%$q%');
      return rows.map<String>((m) => m['id'].toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Убираем символы, которые ломают синтаксис фильтров PostgREST
  /// (запятая и скобки разделяют условия внутри or(...)).
  String _sanitize(String query) =>
      query.trim().replaceAll(RegExp(r'[,()"\\]'), ' ').trim();

  /// Лента «вдохновения» для главной с пагинацией (range).
  Future<List<Product>> feed({int limit = 20, int offset = 0}) async {
    try {
      final rows = await supabase
          .from('products')
          .select(productSelect)
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
          .select(productSelect)
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
