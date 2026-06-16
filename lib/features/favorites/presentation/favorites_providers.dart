import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/domain/product.dart';

/// Множество id избранного с оптимистичным переключением.
class FavoriteIdsNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    ref.watch(authStateProvider); // перечитываем при смене пользователя
    return ref.read(favoritesRepositoryProvider).ids();
  }

  bool contains(String id) => state.valueOrNull?.contains(id) ?? false;

  /// Переключить избранное: меняем состояние сразу, в фоне пишем в базу.
  Future<void> toggle(String productId) async {
    final repo = ref.read(favoritesRepositoryProvider);
    final current = {...?state.valueOrNull};
    final adding = !current.contains(productId);

    // оптимистичное обновление UI
    adding ? current.add(productId) : current.remove(productId);
    state = AsyncData(current);

    try {
      adding ? await repo.add(productId) : await repo.remove(productId);
    } catch (_) {
      // откат при ошибке
      final reverted = {...current};
      adding ? reverted.remove(productId) : reverted.add(productId);
      state = AsyncData(reverted);
      rethrow;
    }
    ref.invalidate(favoriteProductsProvider);
  }
}

final favoriteIdsProvider =
    AsyncNotifierProvider<FavoriteIdsNotifier, Set<String>>(
        FavoriteIdsNotifier.new);

/// Избранные товары целиком (для экрана «Избранное»).
final favoriteProductsProvider = FutureProvider<List<Product>>((ref) {
  ref.watch(authStateProvider);
  ref.watch(favoriteIdsProvider); // обновляемся при изменении набора
  return ref.read(favoritesRepositoryProvider).products();
});
