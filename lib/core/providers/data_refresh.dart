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
  catalogResultsProvider,
  searchResultsProvider,
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
