import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/providers.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/catalog/data/catalog_repository.dart';
import '../../features/catalog/domain/category.dart';
import '../../features/catalog/domain/product.dart';
import '../../features/collections/data/collections_repository.dart';
import '../../features/collections/domain/collection.dart';
import '../../features/favorites/data/favorites_repository.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/notifications/domain/price_drop.dart';
import '../../features/product/data/events_repository.dart';
import '../../features/product/data/reviews_repository.dart';
import '../../features/product/domain/review.dart';
import '../../features/supplier_cabinet/data/storage_repository.dart';
import '../../features/supplier_cabinet/data/supplier_cabinet_repository.dart';
import '../../features/suppliers_map/data/supplier_repository.dart';
import '../../features/suppliers_map/domain/supplier.dart';
import '../errors/failure.dart';
import 'demo_data.dart';

/// Подмена всех репозиториев демо-версиями (для ProviderScope.overrides).
List<Override> demoOverrides() => [
      authRepositoryProvider.overrideWithValue(const DemoAuthRepository()),
      catalogRepositoryProvider.overrideWithValue(const DemoCatalogRepository()),
      favoritesRepositoryProvider
          .overrideWithValue(const DemoFavoritesRepository()),
      collectionsRepositoryProvider
          .overrideWithValue(const DemoCollectionsRepository()),
      reviewsRepositoryProvider
          .overrideWithValue(const DemoReviewsRepository()),
      supplierRepositoryProvider
          .overrideWithValue(const DemoSupplierRepository()),
      eventsRepositoryProvider.overrideWithValue(const DemoEventsRepository()),
      supplierCabinetRepositoryProvider
          .overrideWithValue(const DemoCabinetRepository()),
      storageRepositoryProvider
          .overrideWithValue(const DemoStorageRepository()),
      notificationsRepositoryProvider
          .overrideWithValue(const DemoNotificationsRepository()),
    ];

// ── Авторизация ──
class DemoAuthRepository extends AuthRepository {
  const DemoAuthRepository();

  @override
  Stream<AuthState> get authState => const Stream<AuthState>.empty();

  @override
  bool get isSignedIn => true;

  @override
  Future<AppUser?> myProfile() async => DemoData.user;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updateCity(String city) async {}

  @override
  Future<void> signInEmail(
      {required String email, required String password}) async {}

  @override
  Future<void> signUpEmail({
    required String email,
    required String password,
    required String fullName,
    String city = 'Астана',
    String? phone,
  }) async {}

  @override
  Future<void> signInWithProvider(OAuthProvider provider) async {}

  @override
  Future<void> sendPhoneOtp(String phone) async {}

  @override
  Future<void> verifyPhoneOtp(
      {required String phone, required String token}) async {}

  @override
  Future<void> updateNotifyPrefs(
      {required bool enabled, required int threshold}) async {}

  @override
  Future<void> deleteAccount() async {}
}

// ── Каталог ──
class DemoCatalogRepository extends CatalogRepository {
  const DemoCatalogRepository();

  @override
  Future<List<Category>> categories() async => DemoData.categories;

  @override
  Future<List<Product>> byCategory(String slug) async =>
      DemoData.products.where((p) => p.categorySlug == slug).toList();

  @override
  Future<List<Product>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return DemoData.products
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.sku.toLowerCase().contains(q) ||
            p.brand.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<Product>> feed({int limit = 20, int offset = 0}) async =>
      DemoData.products.skip(offset).take(limit).toList();

  @override
  Future<Product> byId(String id) async {
    final p = DemoData.productById(id);
    if (p == null) throw const Failure('Товар не найден');
    return p;
  }
}

// ── Избранное ──
class DemoFavoritesRepository extends FavoritesRepository {
  const DemoFavoritesRepository();

  @override
  Future<Set<String>> ids() async => {...DemoData.favorites};

  @override
  Future<List<Product>> products() async =>
      DemoData.products.where((p) => DemoData.favorites.contains(p.id)).toList();

  @override
  Future<void> add(String productId) async => DemoData.favorites.add(productId);

  @override
  Future<void> remove(String productId) async =>
      DemoData.favorites.remove(productId);
}

// ── Подборки ──
class DemoCollectionsRepository extends CollectionsRepository {
  const DemoCollectionsRepository();

  int _idx(String id) => DemoData.collections.indexWhere((c) => c.id == id);

  @override
  Future<List<Collection>> list() async =>
      List<Collection>.from(DemoData.collections);

  @override
  Future<Collection> ensureDefault() async {
    if (DemoData.collections.isNotEmpty) return DemoData.collections.first;
    final c = Collection(id: _newId('c'), name: 'Мой проект', items: const []);
    DemoData.collections.add(c);
    return c;
  }

  @override
  Future<String> create(String name) async {
    final id = _newId('c');
    DemoData.collections.add(Collection(id: id, name: name, items: const []));
    return id;
  }

  @override
  Future<void> rename(String collectionId, String name) async {
    final i = _idx(collectionId);
    if (i < 0) return;
    final c = DemoData.collections[i];
    DemoData.collections[i] =
        Collection(id: c.id, name: name, items: c.items, createdAt: c.createdAt);
  }

  @override
  Future<void> deleteCollection(String collectionId) async =>
      DemoData.collections.removeWhere((c) => c.id == collectionId);

  @override
  Future<void> addItem({
    required String collectionId,
    required String productId,
    double qty = 1,
  }) async {
    final i = _idx(collectionId);
    if (i < 0) return;
    final c = DemoData.collections[i];
    if (c.items.any((it) => it.productId == productId)) return;
    final items = [
      ...c.items,
      CollectionItem(
        id: _newId('ci'),
        productId: productId,
        qty: qty,
        product: DemoData.productById(productId),
      ),
    ];
    DemoData.collections[i] =
        Collection(id: c.id, name: c.name, items: items, createdAt: c.createdAt);
  }

  @override
  Future<void> setQty({
    required String collectionId,
    required String productId,
    required double qty,
  }) async {
    final i = _idx(collectionId);
    if (i < 0) return;
    final c = DemoData.collections[i];
    final items = qty <= 0
        ? c.items.where((it) => it.productId != productId).toList()
        : c.items
            .map((it) => it.productId == productId ? it.copyWith(qty: qty) : it)
            .toList();
    DemoData.collections[i] =
        Collection(id: c.id, name: c.name, items: items, createdAt: c.createdAt);
  }

  @override
  Future<void> removeItem({
    required String collectionId,
    required String productId,
  }) async {
    final i = _idx(collectionId);
    if (i < 0) return;
    final c = DemoData.collections[i];
    DemoData.collections[i] = Collection(
      id: c.id,
      name: c.name,
      items: c.items.where((it) => it.productId != productId).toList(),
      createdAt: c.createdAt,
    );
  }

  String _newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}';
}

// ── Отзывы ──
class DemoReviewsRepository extends ReviewsRepository {
  const DemoReviewsRepository();

  @override
  Future<List<Review>> forProduct(String productId) async => const [];

  @override
  Future<void> submit({
    required String productId,
    required int rating,
    String? text,
  }) async {}
}

// ── Поставщики ──
class DemoSupplierRepository extends SupplierRepository {
  const DemoSupplierRepository();

  @override
  Future<List<Supplier>> nearby({
    required double lat,
    required double lng,
    double radiusM = 30000,
  }) async =>
      DemoData.suppliers;

  @override
  Future<List<Supplier>> byCity(String city) async => DemoData.suppliers;

  @override
  Future<Supplier> byId(String id) async {
    final s = DemoData.suppliers.where((x) => x.id == id).toList();
    if (s.isEmpty) throw const Failure('Поставщик не найден');
    return s.first;
  }

  @override
  Future<List<Product>> products(String supplierId) async => DemoData.products
      .where((p) => p.offers.any((o) => o.supplierId == supplierId))
      .toList();
}

// ── События (статистика) — в демо ничего не пишем ──
class DemoEventsRepository extends EventsRepository {
  const DemoEventsRepository();

  @override
  Future<void> logView(Product product) async {}

  @override
  Future<void> logContact(String productId, String? supplierId) async {}
}

// ── Кабинет поставщика — недоступен в демо ──
class DemoCabinetRepository extends SupplierCabinetRepository {
  const DemoCabinetRepository();
  static const _msg = Failure('Кабинет поставщика недоступен в демо-режиме');

  @override
  Future<Supplier> ensureCompany({
    required String fallbackName,
    required String city,
    String? phone,
  }) async =>
      throw _msg;

  @override
  Future<List<Product>> myProducts() async => const [];

  @override
  Future<Map<String, ProductStat>> stats(String supplierId) async => const {};

  @override
  Future<void> becomeSupplier() async => throw _msg;
}

// ── Уведомления о ценах (демо) ──
class DemoNotificationsRepository extends NotificationsRepository {
  const DemoNotificationsRepository();

  @override
  Future<List<PriceDrop>> list() async => [
        PriceDrop(
          id: 'n1',
          productId: 'p1',
          productName: DemoData.productById('p1')?.name ?? '',
          supplierName: 'Keramo City',
          oldPrice: 4560,
          newPrice: 4290,
          createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
        PriceDrop(
          id: 'n2',
          productId: 'p5',
          productName: DemoData.productById('p5')?.name ?? '',
          supplierName: 'Svet Pro',
          oldPrice: 15600,
          newPrice: 14200,
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ];

  @override
  Future<int> unreadCount() async => 2;

  @override
  Future<void> markAllRead() async {}
}

// ── Storage — недоступен в демо ──
class DemoStorageRepository extends StorageRepository {
  const DemoStorageRepository();

  @override
  Future<String> uploadProductImage(Uint8List bytes, {String ext = 'jpg'}) async =>
      throw const Failure('Загрузка фото недоступна в демо-режиме');
}
