import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../../core/providers/settings_provider.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/domain/product.dart';
import '../../suppliers_map/domain/supplier.dart';
import '../data/supplier_cabinet_repository.dart';

/// Карточка компании текущего поставщика (создаётся при первом входе в кабинет).
final myCompanyProvider = FutureProvider<Supplier>((ref) async {
  final profile = await ref.watch(myProfileProvider.future);
  final city = ref.watch(settingsProvider).city;
  return ref.read(supplierCabinetRepositoryProvider).ensureCompany(
        fallbackName: profile?.fullName ?? '',
        city: profile?.city ?? city,
        phone: profile?.phone,
      );
});

/// Мои товары.
final myProductsProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(authStateProvider);
  return ref.read(supplierCabinetRepositoryProvider).myProducts();
});

/// Статистика по моим товарам (productId -> просмотры/контакты).
final myStatsProvider =
    FutureProvider<Map<String, ProductStat>>((ref) async {
  final company = await ref.watch(myCompanyProvider.future);
  return ref.read(supplierCabinetRepositoryProvider).stats(company.id);
});

/// Действия кабинета (добавление/сохранение/удаление/импорт).
class CabinetController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      ref.invalidate(myProductsProvider);
      ref.invalidate(myStatsProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> addProduct({
    required String name,
    required String categorySlug,
    required String unit,
    required double price,
    required bool inStock,
    required String supplierId,
    String? sku,
    String? imageUrl,
  }) =>
      _run(() => ref.read(supplierCabinetRepositoryProvider).addProduct(
            name: name,
            categorySlug: categorySlug,
            unit: unit,
            price: price,
            inStock: inStock,
            supplierId: supplierId,
            sku: sku,
            imageUrl: imageUrl,
          ));

  Future<bool> saveOffer({
    String? offerId,
    required String productId,
    required String supplierId,
    required double price,
    required bool inStock,
  }) =>
      _run(() => ref.read(supplierCabinetRepositoryProvider).saveOffer(
            offerId: offerId,
            productId: productId,
            supplierId: supplierId,
            price: price,
            inStock: inStock,
          ));

  Future<bool> deleteProduct(String productId) => _run(
      () => ref.read(supplierCabinetRepositoryProvider).deleteProduct(productId));

  /// Импорт прайса. Возвращает число загруженных позиций или -1 при ошибке.
  Future<int> importPrice({
    required List<PriceRow> rows,
    required String categorySlug,
    required String supplierId,
  }) async {
    state = const AsyncLoading();
    try {
      final n = await ref.read(supplierCabinetRepositoryProvider).importPrice(
            rows: rows,
            categorySlug: categorySlug,
            supplierId: supplierId,
          );
      ref.invalidate(myProductsProvider);
      ref.invalidate(myStatsProvider);
      state = const AsyncData(null);
      return n;
    } catch (e, st) {
      state = AsyncError(e, st);
      return -1;
    }
  }

  Future<bool> becomeSupplier() async {
    final ok = await _run(
        () => ref.read(supplierCabinetRepositoryProvider).becomeSupplier());
    if (ok) ref.invalidate(myProfileProvider);
    return ok;
  }
}

final cabinetControllerProvider =
    AsyncNotifierProvider<CabinetController, void>(CabinetController.new);
