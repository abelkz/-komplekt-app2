import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/skeletons.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/widgets/product_card.dart';
import 'favorites_providers.dart';

/// Экран 7 — Избранное: товары, за ценой которых следит пользователь.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoriteProductsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Text('Избранное', style: AppTypography.unbounded()),
            ),
            Expanded(
              child: AsyncValueView<List<Product>>(
                value: favs,
                loading: const SkeletonList(),
                onRetry: () => ref.invalidate(favoriteProductsProvider),
                isEmpty: (d) => d.isEmpty,
                empty: const EmptyState(
                  title: 'Пока пусто',
                  subtitle:
                      'Нажмите на сердечко в карточке товара, чтобы следить за ценой.',
                  icon: Icons.favorite_border,
                ),
                data: (list) => RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(favoriteProductsProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SpecDivider(),
                    // Смахивание влево убирает товар из избранного —
                    // так же, как в подборках
                    itemBuilder: (_, i) => Dismissible(
                      key: ValueKey('fav-${list[i].id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        padding: const EdgeInsets.only(right: 22),
                        alignment: Alignment.centerRight,
                        color: context.colors.red,
                        child: const Icon(Icons.delete_outline,
                            color: Colors.white, size: 26),
                      ),
                      onDismissed: (_) => _remove(context, ref, list[i]),
                      child: ProductCard(product: list[i], index: i),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Убрать из избранного с возможностью вернуть — смахнуть можно случайно.
  Future<void> _remove(
      BuildContext context, WidgetRef ref, Product product) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(favoriteIdsProvider.notifier);
    try {
      await notifier.toggle(product.id);
      messenger.showSnackBar(SnackBar(
        content: Text('${product.name} убран из избранного'),
        action: SnackBarAction(
          label: 'Вернуть',
          onPressed: () => notifier.toggle(product.id).catchError((_) {}),
        ),
      ));
    } catch (e) {
      final t = e.toString();
      messenger.showSnackBar(SnackBar(
          content: Text(t.startsWith('Failure: ')
              ? t.substring(9)
              : 'Не удалось убрать из избранного')));
    }
  }
}
