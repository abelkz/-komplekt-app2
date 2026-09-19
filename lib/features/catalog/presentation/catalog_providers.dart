import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../domain/category.dart';
import '../domain/price_drop.dart';
import '../domain/product.dart';

/// Способ сортировки результатов.
enum SortBy { priceAsc, priceDesc, rating }

extension SortByLabel on SortBy {
  String get label => switch (this) {
        SortBy.priceAsc => 'Сначала дешевле',
        SortBy.priceDesc => 'Сначала дороже',
        SortBy.rating => 'По рейтингу',
      };
}

/// Фильтры каталога (как в bottom-sheet прототипа + сортировка).
class CatalogFilters {
  const CatalogFilters({
    this.city = 'Все города',
    this.inStock = false,
    this.sort = SortBy.priceAsc,
    this.maxPrice,
    this.brand,
  });

  final String city;
  final bool inStock;
  final SortBy sort;

  /// Потолок цены за единицу. null — без ограничения. Бюджет на материал
  /// задают сверху («плитка до 5 000 за м²»), а не диапазоном.
  final double? maxPrice;

  /// Марка. null — все. Сравнивается по названию: у товара марка приезжает
  /// строкой из brands(name), своего идентификатора в карточке нет.
  final String? brand;

  int get activeCount =>
      (city != 'Все города' ? 1 : 0) +
      (inStock ? 1 : 0) +
      (maxPrice != null ? 1 : 0) +
      (brand != null ? 1 : 0);

  /// Сброс необязательного фильтра отдельными флагами: через `null`
  /// в copyWith «убрать потолок цены» неотличимо от «не трогать его».
  CatalogFilters copyWith({
    String? city,
    bool? inStock,
    SortBy? sort,
    double? maxPrice,
    String? brand,
    bool clearMaxPrice = false,
    bool clearBrand = false,
  }) =>
      CatalogFilters(
        city: city ?? this.city,
        inStock: inStock ?? this.inStock,
        sort: sort ?? this.sort,
        maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
        brand: clearBrand ? null : (brand ?? this.brand),
      );
}

class FiltersNotifier extends Notifier<CatalogFilters> {
  @override
  CatalogFilters build() => const CatalogFilters();

  void apply(CatalogFilters f) => state = f;
  void reset() => state = const CatalogFilters();
}

final filtersProvider =
    NotifierProvider<FiltersNotifier, CatalogFilters>(FiltersNotifier.new);

/// Применение фильтров и сортировки к списку товаров (на стороне клиента,
/// как в прототипе: фильтруем предложения по городу/наличию).
List<Product> applyFilters(List<Product> products, CatalogFilters f) {
  final result = <Product>[];
  for (final p in products) {
    // Марка — свойство карточки, а не предложения: отсекаем товар целиком.
    final brand = f.brand;
    if (brand != null && p.brand.toLowerCase() != brand.toLowerCase()) continue;

    var offers = p.offers;
    if (f.city != 'Все города') {
      offers = offers.where((o) => o.city == f.city).toList();
    }
    if (f.inStock) offers = offers.where((o) => o.inStock).toList();
    // Потолок применяем к предложениям, а не к минимальной цене товара:
    // иначе в карточке остались бы строки дороже заданного бюджета.
    final cap = f.maxPrice;
    if (cap != null) offers = offers.where((o) => o.price <= cap).toList();
    if (offers.isEmpty) continue;
    result.add(Product(
      id: p.id,
      name: p.name,
      categorySlug: p.categorySlug,
      brand: p.brand,
      sku: p.sku,
      unit: p.unit,
      color: p.color,
      description: p.description,
      rating: p.rating,
      images: p.images,
      offers: offers,
      // Пересобирая товар ради отфильтрованных предложений, легко потерять
      // поля, добавленные позже. Фасовка, гарантия и характеристики уже
      // приезжают из базы — и без этих трёх строк они исчезали по дороге
      // в каталог и поиск, а карточка молча теряла характеристики.
      packQty: p.packQty,
      warrantyMonths: p.warrantyMonths,
      attrs: p.attrs,
    ));
  }
  result.sort((a, b) {
    switch (f.sort) {
      case SortBy.priceAsc:
        return (a.minPrice ?? 0).compareTo(b.minPrice ?? 0);
      case SortBy.priceDesc:
        return (b.minPrice ?? 0).compareTo(a.minPrice ?? 0);
      case SortBy.rating:
        return b.rating.compareTo(a.rating);
    }
  });
  return result;
}

// ── Данные ──

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(catalogRepositoryProvider).categories();
});

/// Марки каталога — подсказки в форме товара у поставщика.
final allBrandsProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(catalogRepositoryProvider).brands();
});

/// Лента вдохновения для главной (Pinterest-masonry) с пагинацией.
class FeedNotifier extends AsyncNotifier<List<Product>> {
  static const _pageSize = 20;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  @override
  Future<List<Product>> build() async {
    final first = await ref
        .read(catalogRepositoryProvider)
        .feed(limit: _pageSize, offset: 0);
    _hasMore = first.length == _pageSize;
    return first;
  }

  /// Догрузить следующую страницу (вызывается кнопкой «Показать ещё»).
  Future<void> loadMore() async {
    if (!_hasMore) return;
    final current = state.valueOrNull ?? const [];
    final next = await ref
        .read(catalogRepositoryProvider)
        .feed(limit: _pageSize, offset: current.length);
    _hasMore = next.length == _pageSize;
    state = AsyncData([...current, ...next]);
  }
}

final feedProvider =
    AsyncNotifierProvider<FeedNotifier, List<Product>>(FeedNotifier.new);

/// Окно, за которое считаем снижения. Месяц, а не неделя: проверено на живой
/// базе 18.09.2026 — за 7 дней снижений нет ни одного, за 30 дней ровно одно.
/// Поставщики правят прайс редко, и недельное окно оставляло бы секцию
/// всегда пустой. Когда каталог оживёт, окно стоит вернуть к неделе —
/// заодно поменяв подпись секции на главной.
const priceDropsDays = 30;

/// Реальные снижения минимальной цены за [priceDropsDays].
///
/// Пустой список — нормальное состояние, а не ошибка: если никто не снижал
/// цену, секцию на главной просто не показываем. Врать «смотрите,
/// подешевело», когда не подешевело, нельзя.
final priceDropsProvider = FutureProvider<List<PriceDrop>>((ref) async {
  try {
    return await ref
        .watch(catalogRepositoryProvider)
        .priceDrops(days: priceDropsDays);
  } catch (_) {
    // Миграция 0027 могла быть ещё не применена к базе — в этом случае
    // главная должна открыться как обычно, просто без этой секции.
    return const [];
  }
});

/// Товары категории как они есть в базе, без фильтров.
///
/// Отделено от результатов нарочно: фильтры применяются на клиенте, и пока
/// запрос к базе сидел в том же провайдере, каждое переключение чипа
/// перезапрашивало всю категорию по сети. Отсюда же берётся список марок
/// для чипов — по отфильтрованному списку он схлопывался бы до одной марки
/// сразу после первого выбора.
final categoryProductsProvider =
    FutureProvider.family<List<Product>, String>((ref, slug) {
  return ref.watch(catalogRepositoryProvider).byCategory(slug);
});

/// Товары категории с применёнными фильтрами.
final catalogResultsProvider =
    FutureProvider.family<List<Product>, String>((ref, slug) async {
  final products = await ref.watch(categoryProductsProvider(slug).future);
  return applyFilters(products, ref.watch(filtersProvider));
});

/// Найденные товары без фильтров.
final searchProductsProvider =
    FutureProvider.family<List<Product>, String>((ref, query) {
  return ref.watch(catalogRepositoryProvider).search(query);
});

/// Результаты поиска по строке запроса.
final searchResultsProvider =
    FutureProvider.family<List<Product>, String>((ref, query) async {
  final products = await ref.watch(searchProductsProvider(query).future);
  return applyFilters(products, ref.watch(filtersProvider));
});

/// Сколько товаров набора есть в наличии хотя бы у одного поставщика.
int inStockCountOf(List<Product> products) =>
    products.where((p) => p.offers.any((o) => o.inStock)).length;

/// Марки, которые вообще встречаются в этом наборе товаров.
///
/// Чипы марок показываем, только если марок больше одной: в категории
/// с единственным брендом такой чип ничего не фильтрует и лишь занимает
/// строку.
List<String> brandsOf(List<Product> products) {
  final set = <String>{};
  for (final p in products) {
    if (p.brand.trim().isNotEmpty) set.add(p.brand.trim());
  }
  if (set.length < 2) return const [];
  final list = set.toList()..sort();
  return list;
}

/// Недавние поиски (персистятся в SharedPreferences).
class RecentSearchesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => ref.read(localStoreProvider).recentSearches;

  void add(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    final next = [q, ...state.where((x) => x != q)].take(5).toList();
    state = next;
    ref.read(localStoreProvider).setRecentSearches(next);
  }

  void clear() {
    state = [];
    ref.read(localStoreProvider).setRecentSearches(const []);
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
        RecentSearchesNotifier.new);
