import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/local_store.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/catalog/data/catalog_repository.dart';
import '../../features/collections/data/collections_repository.dart';
import '../../features/favorites/data/favorites_repository.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/product/data/events_repository.dart';
import '../../features/product/data/reviews_repository.dart';
import '../../features/supplier_cabinet/data/storage_repository.dart';
import '../../features/supplier_cabinet/data/supplier_cabinet_repository.dart';
import '../../features/subscription/data/subscription_repository.dart';
import '../../features/suppliers_map/data/supplier_repository.dart';
import '../../features/visual_search/data/visual_search_repository.dart';

/// Локальное хранилище — переопределяется в main.dart реальным экземпляром.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider не инициализирован'),
);

// ── Репозитории (единые экземпляры на всё приложение) ──
final authRepositoryProvider = Provider((ref) => const AuthRepository());
final catalogRepositoryProvider = Provider((ref) => const CatalogRepository());
final reviewsRepositoryProvider = Provider((ref) => const ReviewsRepository());
final supplierRepositoryProvider = Provider((ref) => const SupplierRepository());
final favoritesRepositoryProvider =
    Provider((ref) => const FavoritesRepository());
final collectionsRepositoryProvider =
    Provider((ref) => const CollectionsRepository());
final eventsRepositoryProvider = Provider((ref) => const EventsRepository());
final supplierCabinetRepositoryProvider =
    Provider((ref) => const SupplierCabinetRepository());
final storageRepositoryProvider = Provider((ref) => const StorageRepository());
final notificationsRepositoryProvider =
    Provider((ref) => const NotificationsRepository());
final visualSearchRepositoryProvider =
    Provider((ref) => const VisualSearchRepository());
final subscriptionRepositoryProvider =
    Provider((ref) => const SubscriptionRepository());
