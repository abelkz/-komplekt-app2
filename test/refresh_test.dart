import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komplekt/core/providers/data_refresh.dart';
import 'package:komplekt/core/providers/providers.dart';
import 'package:komplekt/features/catalog/data/catalog_repository.dart';
import 'package:komplekt/features/catalog/domain/offer.dart';
import 'package:komplekt/features/catalog/domain/product.dart';
import 'package:komplekt/features/catalog/presentation/catalog_providers.dart';

/// Каталог, у которого можно «выдернуть шнур»: считает обращения и по
/// команде начинает падать — как сеть в лифте.
class _FakeCatalog extends CatalogRepository {
  int calls = 0;
  bool fail = false;

  @override
  Future<List<Product>> byCategory(String slug) async {
    calls++;
    if (fail) throw Exception('нет связи');
    return const [
      Product(id: 'a', name: 'A', offers: [
        Offer(price: 4290, inStock: true, supplierId: 's1', city: 'Астана'),
      ]),
      Product(id: 'b', name: 'B', offers: [
        Offer(price: 3150, inStock: false, supplierId: 's2', city: 'Астана'),
      ]),
    ];
  }
}

/// «Обновить всё приложение» вызывается из виджетов и контроллеров, а в
/// тесте нет ни того ни другого — берём `Ref` у провайдера-пустышки.
final _refreshAll = Provider<void Function()>(
  (ref) => () => invalidateAppData(ref),
);

void main() {
  late _FakeCatalog repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeCatalog();
    container = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    // Экран категории открыт: без слушателя провайдер никто не
    // перестраивает, и проверять было бы нечего.
    container.listen(catalogResultsProvider('tile'), (_, __) {});
  });

  test('«обновить» действительно ходит в базу за товарами категории',
      () async {
    // Ровно это и было сломано: в списке обновляемого стояли результаты
    // с фильтрами, а не сам набор. Обновление пересчитывало фильтры по
    // уже загруженному и в сеть не ходило вовсе.
    await container.read(catalogResultsProvider('tile').future);
    expect(repo.calls, 1);

    container.read(_refreshAll)();
    await container.read(catalogResultsProvider('tile').future);

    expect(repo.calls, 2);
  });

  test('неудачное обновление не стирает список и не ломает фильтры',
      () async {
    expect(
      (await container.read(catalogResultsProvider('tile').future)).length,
      2,
    );

    repo.fail = true;
    await expectLater(
      container.refresh(categoryProductsProvider('tile').future),
      throwsA(anything),
    );

    // Сам набор в ошибке, но прежние данные при нём остались…
    final base = container.read(categoryProductsProvider('tile'));
    expect(base.hasError, isTrue);
    expect(base.hasValue, isTrue);

    // …и результаты отдают их, а не ошибку.
    expect(
      (await container.read(catalogResultsProvider('tile').future)).length,
      2,
    );

    // Главное: фильтр по-прежнему что-то делает. Без запасного пути
    // результаты застревали в ошибке, а экран показывал прежний список,
    // на котором чипы молча переставали работать.
    container
        .read(filtersProvider.notifier)
        .apply(const CatalogFilters(inStock: true));
    final filtered =
        await container.read(catalogResultsProvider('tile').future);
    expect(filtered.map((p) => p.id), ['a']);
  });

  test('после неудачи следующее обновление подтягивает свежие данные',
      () async {
    await container.read(catalogResultsProvider('tile').future);

    repo.fail = true;
    await expectLater(
      container.refresh(categoryProductsProvider('tile').future),
      throwsA(anything),
    );

    repo.fail = false;
    await container.refresh(categoryProductsProvider('tile').future);

    final base = container.read(categoryProductsProvider('tile'));
    expect(base.hasError, isFalse);
    expect(
      (await container.read(catalogResultsProvider('tile').future)).length,
      2,
    );
  });
}
