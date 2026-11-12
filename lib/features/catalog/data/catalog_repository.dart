import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/category.dart';
import '../domain/price_drop.dart';
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
  //
  // pack_qty, warranty_months, attrs, stock_qty и lead_time_days добавлены
  // миграцией 0029. Если её не накатить на базу, весь запрос упадёт с 42703
  // — порядок здесь строгий: сначала миграция, потом сборка с этим кодом.
  static const productSelect =
      'id,name,sku,unit,color,image_url,description,rating,category_slug,'
      'brand_id,pack_qty,warranty_months,attrs,'
      'brands(name),'
      'product_images(url,sort),'
      'offers(id,price,prev_price,in_stock,price_updated_at,promoted_until,'
      'product_url,'
      'stock_qty,lead_time_days,supplier_id,'
      'suppliers(name,city,phone,whatsapp,website,verified,plan,plan_until))';

  /// То же, но только товары, у которых есть хотя бы одно предложение:
  /// `!inner` превращает вложенную выборку во внутреннее соединение.
  ///
  /// Нужно для ленты на главной. Карточка без единой цены в каталоге
  /// законна — это справочник, по нему видно, что товар знают, и видно
  /// спрос. Но лента отсортирована по дате добавления, поэтому пачка
  /// заведённых справочных карточек заняла бы её целиком, и первое, что
  /// увидел бы покупатель, — экран из «цена не указана».
  static const productSelectPricedOnly =
      'id,name,sku,unit,color,image_url,description,rating,category_slug,'
      'brand_id,pack_qty,warranty_months,attrs,'
      'brands(name),'
      'product_images(url,sort),'
      'offers!inner(id,price,prev_price,in_stock,price_updated_at,product_url,'
      'promoted_until,stock_qty,lead_time_days,supplier_id,'
      'suppliers(name,city,phone,whatsapp,website,verified,plan,plan_until))';

  /// Карточки без цены — в конец списка.
  ///
  /// Не сортировка, а разделение на две части: внутри каждой порядок
  /// остаётся тот, что пришёл из базы (List.sort в Dart неустойчив и
  /// перемешал бы их).
  static List<Product> _pricedFirst(List<Product> list) => [
        ...list.where((p) => p.minPrice != null),
        ...list.where((p) => p.minPrice == null),
      ];

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

  /// Все марки каталога — для подсказок в форме товара.
  ///
  /// Ошибку не поднимаем: подсказки удобство, а не условие работы формы.
  /// Не загрузились — поставщик просто впишет марку руками.
  Future<List<String>> brands() async {
    try {
      final rows = await supabase.from('brands').select('name').order('name');
      return [
        for (final m in rows)
          if ((m['name'] as String?)?.trim().isNotEmpty == true)
            (m['name'] as String).trim(),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Товары, у которых минимальная цена упала за последние [days] дней.
  ///
  /// Считает база (RPC `price_drops`, миграция 0027): таблица price_history
  /// закрыта тарифом Про, а главную смотрит и гость, поэтому наружу отдаётся
  /// только агрегат — насколько упала минимальная цена. Пустой ответ здесь
  /// нормален: если за неделю никто не снижал цену, показывать нечего.
  Future<List<PriceDrop>> priceDrops({int days = 7, int limit = 12}) async {
    try {
      final rows = await supabase
          .rpc('price_drops', params: {'p_days': days, 'p_limit': limit});
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return const [];

      // Порядок из RPC — по величине падения; PostgREST его не сохранит,
      // поэтому восстанавливаем по исходному списку.
      final order = [for (final r in list) r['product_id'].toString()];
      final products = await supabase
          .from('products')
          .select(productSelect)
          .inFilter('id', [for (final r in list) r['product_id']]);

      final byId = {
        for (final m in products)
          m['id'].toString(): Product.fromMap(m as Map<String, dynamic>),
      };

      return [
        for (final r in list)
          if (byId[r['product_id'].toString()] != null)
            PriceDrop(
              product: byId[r['product_id'].toString()]!,
              oldPrice: (r['old_price'] as num).toDouble(),
              newPrice: (r['new_price'] as num).toDouble(),
              percent: (r['pct'] as num).round(),
            ),
      ]..sort((a, b) =>
          order.indexOf(a.product.id).compareTo(order.indexOf(b.product.id)));
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить снижения цен');
    }
  }

  /// Товары, у которых несколько продавцов и цены расходятся.
  ///
  /// Считает база (RPC `price_spread`, миграция 0046) и по всему каталогу.
  /// Раньше секция «Где цены расходятся» набиралась из первой страницы
  /// ленты — 20 самых новых карточек, — и показывала товары с одной ценой,
  /// то есть обещала выгоду там, где её нет. Разброс это свойство карточки,
  /// а не того, что приложение успело загрузить.
  ///
  /// Возвращаем готовые [Product], а не отдельную модель: процент на
  /// карточке считает `savingPercent` из тех же предложений, поэтому цифра
  /// в секции и цифра на карточке совпадают по построению.
  ///
  /// Пустой список нормален: если у всех товаров по одному продавцу,
  /// сравнивать нечего и секцию показывать не надо.
  Future<List<Product>> priceSpread({int limit = 12}) async {
    final rows = await supabase.rpc('price_spread', params: {'p_limit': limit});
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return const [];

    // Порядок из RPC — по величине разрыва; PostgREST его не сохранит,
    // поэтому восстанавливаем по исходному списку.
    final order = [for (final r in list) r['product_id'].toString()];
    final products = await supabase
        .from('products')
        .select(productSelect)
        .inFilter('id', [for (final r in list) r['product_id']]);

    return products.map<Product>((m) => Product.fromMap(m)).toList()
      ..sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));
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
      //
      // Справочные карточки (без единой цены) из категории не прячем:
      // по ним видно, что товар в каталоге знают, и видно спрос. Но
      // показывать их раньше того, что можно купить, нельзя.
      return _pricedFirst(rows.map<Product>((m) => Product.fromMap(m)).toList());
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
      return _pricedFirst(rows.map<Product>((m) => Product.fromMap(m)).toList());
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
          .select(productSelectPricedOnly)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map<Product>((m) => Product.fromMap(m)).toList();
    } catch (e) {
      // `!inner` могла не понять старая версия PostgREST. Лента важнее
      // фильтрации: лучше показать её с карточками без цены, чем не
      // показать вовсе.
      try {
        final rows = await supabase
            .from('products')
            .select(productSelect)
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
        return _pricedFirst(
            rows.map<Product>((m) => Product.fromMap(m)).toList());
      } catch (_) {}
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
