import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/admin/presentation/admin_providers.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/catalog/presentation/catalog_providers.dart';
import '../../features/collections/presentation/collections_providers.dart';
import '../../features/favorites/presentation/favorites_providers.dart';
import '../../features/notifications/presentation/notifications_providers.dart';
import '../../features/product/data/price_history_repository.dart';
import '../../features/product/presentation/product_providers.dart';
import '../../features/supplier_cabinet/presentation/supplier_cabinet_providers.dart';
import '../../features/suppliers_map/presentation/suppliers_providers.dart';

/// Всё, что читается из базы и может устареть.
///
/// Провайдеры Riverpod держат загруженный ответ до перезапуска приложения:
/// именно поэтому включённый тариф или новая цена раньше появлялись только
/// после закрытия и открытия. Пометив их устаревшими, мы заставляем
/// открытые экраны перезапросить данные.
///
/// Настроек и недавних поисков здесь нет: они локальные, свежей версии
/// на сервере у них не бывает.
final _volatile = <ProviderOrFamily>[
  myProfileProvider,

  // Каталог и карточки товаров
  feedProvider,
  categoriesProvider,
  // Именно наборы, а не catalogResults / searchResults: результаты лишь
  // накладывают фильтры на уже загруженный набор и перестраиваются за
  // ним сами. Пока здесь стояли результаты, «обновить» пересчитывало
  // фильтры по старым данным и в сеть не ходило вовсе — так вышло, когда
  // запрос к базе отделили от фильтров, а этот список не поправили.
  categoryProductsProvider,
  searchProductsProvider,
  priceDropsProvider,
  priceSpreadProvider,
  productProvider,
  reviewsProvider,
  priceHistoryProvider,

  // Личные данные
  favoriteIdsProvider,
  favoriteProductsProvider,
  collectionsProvider,
  notificationsProvider,
  unreadCountProvider,

  // Кабинет поставщика
  myCompanyProvider,
  myProductsProvider,
  myStatsProvider,
  boostStatusProvider,

  // Панель администратора
  supplierApplicationsProvider,
  subscriptionRequestsProvider,
  boostOrdersProvider,

  // Поставщики
  nearbySuppliersProvider,
  supplierProvider,
  supplierProductsProvider,
];

/// Обновить данные приложения из провайдера/контроллера.
void invalidateAppData(Ref ref) {
  for (final p in _volatile) {
    ref.invalidate(p);
  }
}

/// Обновить данные приложения из виджета.
void refreshAppData(WidgetRef ref) {
  for (final p in _volatile) {
    ref.invalidate(p);
  }
}

/// Меньше этого индикатор обновления не показываем.
///
/// База отвечает за сотню миллисекунд, и индикатор успевал только
/// мелькнуть. Данные при этом обычно те же, что были, — и у человека не
/// оставалось ни одного признака, что обновление вообще произошло.
const _minSpinner = Duration(milliseconds: 600);

/// Запас поверх таймаута запросов (20 с, см. `TimeoutHttpClient`):
/// индикатор не должен крутиться вечно ни при каком раскладе.
const _refreshTimeout = Duration(seconds: 25);

/// Жест «потянуть — обновить»: перезапросить и ДОЖДАТЬСЯ ответа.
///
/// [refresh] возвращает то, чего ждать, — обычно
/// `ref.refresh(provider.future)` для данных, видимых на экране.
///
/// Раньше обработчики жеста только помечали данные устаревшими
/// (`ref.invalidate`) и тут же возвращались. Пометка мгновенная, поэтому
/// индикатор исчезал раньше, чем уходил запрос, а о сбое человек не
/// узнавал никак: жест выглядел неработающим, даже когда работал.
///
/// При неудаче показывает плашку, а не экран ошибки — уже загруженное
/// остаётся на месте (для этого у `AsyncValueView` есть `keepData`).
Future<void> refreshAndWait(
  BuildContext context,
  List<Future<Object?>> Function() refresh,
) async {
  // Берём заранее: после ожидания экран мог закрыться, а контекст —
  // стать недействительным.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final started = DateTime.now();
  var ok = true;
  try {
    await Future.wait(refresh()).timeout(_refreshTimeout);
  } catch (_) {
    ok = false;
  }
  final left = _minSpinner - DateTime.now().difference(started);
  if (left > Duration.zero) await Future<void>.delayed(left);
  if (!ok) {
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Не удалось обновить — проверьте связь'),
        ),
      );
  }
}

/// То же, но перед этим помечает устаревшим всё приложение.
///
/// Для экранов, где человек ждёт «обнови всё»: главная, каталог, карточка
/// товара, профиль. Перезапросятся только открытые экраны — провайдер, на
/// который никто не смотрит, сходит в сеть при следующем обращении.
Future<void> pullToRefresh(
  BuildContext context,
  WidgetRef ref, {
  List<Future<Object?>> Function()? wait,
}) {
  refreshAppData(ref);
  return refreshAndWait(
    context,
    wait ?? () => const <Future<Object?>>[],
  );
}
