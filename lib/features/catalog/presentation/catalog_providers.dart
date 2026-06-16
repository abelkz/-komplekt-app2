import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../domain/category.dart';
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
  });

  final String city;
  final bool inStock;
  final SortBy sort;

  int get activeCount => (city != 'Все города' ? 1 : 0) + (inStock ? 1 : 0);

  CatalogFilters copyWith({String? city, bool? inStock, SortBy? sort}) =>
      CatalogFilters(
        city: city ?? this.city,
        inStock: inStock ?? this.inStock,
        sort: sort ?? this.sort,
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
    var offers = p.offers;
    if (f.city != 'Все города') {
      offers = offers.where((o) => o.city == f.city).toList();
    }
    if (f.inStock) offers = offers.where((o) => o.inStock).toList();
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

/// Товары категории с применёнными фильтрами.
final catalogResultsProvider =
    FutureProvider.family<List<Product>, String>((ref, slug) async {
  final products = await ref.watch(catalogRepositoryProvider).byCategory(slug);
  return applyFilters(products, ref.watch(filtersProvider));
});

/// Результаты поиска по строке запроса.
final searchResultsProvider =
    FutureProvider.family<List<Product>, String>((ref, query) async {
  final products = await ref.watch(catalogRepositoryProvider).search(query);
  return applyFilters(products, ref.watch(filtersProvider));
});

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
