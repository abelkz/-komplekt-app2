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
      'offers(id,price,prev_price,in_stock,price_updated_at,promoted_until,supplier_id,'
      'suppliers(name,city,phone,whatsapp,website,verified,plan,plan_until))';

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
      // Общую карточку продвижение не поднимает — она общая для всех
      // поставщиков. Продвижение показывается отдельной спонсорской
      // строкой (см. sponsoredInCategory).
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

  /// Оплаченные к показу товары — наверх списка.
  ///
  /// Только в списках и поиске, где нет обещания «здесь дешевле», и только
  /// с пометкой в карточке. Внутри товара шкала цен остаётся строго
  /// по цене — иначе сравнение цен перестаёт быть сравнением цен.
  /// Спонсорские строки для списка товаров: каждое продвигаемое сейчас
  /// предложение — отдельной строкой от имени своего поставщика.
  ///
  /// В отличие от старого «поднять карточку», это рекламирует конкретного
  /// продавца, а не общую карточку со всеми конкурентами.
  static List<SponsoredOffer> sponsoredFrom(List<Product> products,
      {int limit = 3}) {
    final result = <SponsoredOffer>[];
    for (final p in products) {
      for (final o in p.offers) {
        if (o.isPromoted) result.add(SponsoredOffer(product: p, offer: o));
      }
    }
    // Раньше истекает — выше; при равенстве неважно
    result.sort((a, b) => (a.offer.promotedUntil ?? DateTime(2100))
        .compareTo(b.offer.promotedUntil ?? DateTime(2100)));
    return result.take(limit).toList();
  }

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
