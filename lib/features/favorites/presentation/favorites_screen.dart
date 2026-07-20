import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                    itemBuilder: (_, i) => ProductCard(product: list[i], index: i),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
