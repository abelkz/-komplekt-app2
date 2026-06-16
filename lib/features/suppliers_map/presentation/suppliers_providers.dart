import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../catalog/domain/product.dart';
import '../data/location_service.dart';
import '../domain/supplier.dart';

final locationServiceProvider = Provider((ref) => const LocationService());

/// Текущая позиция пользователя (или центр города).
final userLocationProvider = FutureProvider<UserLocation>((ref) {
  return ref.watch(locationServiceProvider).current();
});

/// Поставщики рядом (PostGIS), отсортированы по расстоянию.
final nearbySuppliersProvider = FutureProvider<List<Supplier>>((ref) async {
  final loc = await ref.watch(userLocationProvider.future);
  return ref
      .watch(supplierRepositoryProvider)
      .nearby(lat: loc.lat, lng: loc.lng);
});

/// Карточка поставщика.
final supplierProvider =
    FutureProvider.family<Supplier, String>((ref, id) async {
  return ref.watch(supplierRepositoryProvider).byId(id);
});

/// Витрина: товары поставщика.
final supplierProductsProvider =
    FutureProvider.family<List<Product>, String>((ref, id) async {
  return ref.watch(supplierRepositoryProvider).products(id);
});
