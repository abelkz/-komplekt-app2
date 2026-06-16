import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/collection.dart';

/// Список подборок пользователя + операции над ними.
class CollectionsNotifier extends AsyncNotifier<List<Collection>> {
  @override
  Future<List<Collection>> build() async {
    ref.watch(authStateProvider);
    return ref.read(collectionsRepositoryProvider).list();
  }

  Future<void> _reload() async {
    state = await AsyncValue.guard(
        () => ref.read(collectionsRepositoryProvider).list());
  }

  /// Быстрое добавление товара в подборку по умолчанию (с карточки товара).
  /// Возвращает имя подборки, куда добавили.
  Future<String> addToDefault(String productId) async {
    final repo = ref.read(collectionsRepositoryProvider);
    final col = await repo.ensureDefault();
    await repo.addItem(collectionId: col.id, productId: productId);
    await _reload();
    return col.name;
  }

  Future<void> setQty(
      String collectionId, String productId, double qty) async {
    await ref.read(collectionsRepositoryProvider).setQty(
        collectionId: collectionId, productId: productId, qty: qty);
    await _reload();
  }

  Future<void> removeItem(String collectionId, String productId) async {
    await ref
        .read(collectionsRepositoryProvider)
        .removeItem(collectionId: collectionId, productId: productId);
    await _reload();
  }

  Future<void> create(String name) async {
    await ref.read(collectionsRepositoryProvider).create(name);
    await _reload();
  }

  Future<void> rename(String id, String name) async {
    await ref.read(collectionsRepositoryProvider).rename(id, name);
    await _reload();
  }

  Future<void> remove(String id) async {
    await ref.read(collectionsRepositoryProvider).deleteCollection(id);
    await _reload();
  }
}

final collectionsProvider =
    AsyncNotifierProvider<CollectionsNotifier, List<Collection>>(
        CollectionsNotifier.new);

/// Сколько всего позиций во всех подборках (для бейджа на навбаре).
final collectionsItemCountProvider = Provider<int>((ref) {
  final cols = ref.watch(collectionsProvider).valueOrNull ?? const [];
  return cols.fold<int>(0, (s, c) => s + c.items.length);
});
