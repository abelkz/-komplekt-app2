import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/sign_in_required.dart';
import '../../../core/widgets/skeletons.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/widgets/product_grid_card.dart';
import 'favorites_providers.dart';

/// Экран 7 — Избранное: товары, за ценой которых следит пользователь.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Гостю показывать нечего: избранное хранится за аккаунтом.
    if (!ref.watch(isSignedInProvider)) {
      return const Scaffold(
        body: SafeArea(
          child: SignInRequired(
            icon: Icons.favorite_border,
            title: 'Избранное — после входа',
            subtitle: 'Войдите, чтобы следить за ценой на нужные товары и '
                'получать уведомления, когда они дешевеют.',
          ),
        ),
      );
    }

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
                  // Сердечко на карточке убирает товар из избранного.
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: list.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 264,
                    ),
                    itemBuilder: (_, i) => ProductGridCard(product: list[i]),
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
