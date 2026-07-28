import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/skeletons.dart';
import '../data/catalog_repository.dart';
import '../domain/product.dart';
import 'catalog_providers.dart';
import 'widgets/filters_sheet.dart';
import 'widgets/product_grid_card.dart';

/// Экран 4 — Каталог категории: карточки-картинки с фильтрами и сортировкой.
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key, required this.slug, this.title});

  final String slug;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final results = ref.watch(catalogResultsProvider(slug));
    final filters = ref.watch(filtersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title ?? 'Каталог',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(
              results.maybeWhen(
                data: (d) =>
                    '${d.length} товаров · ${filters.sort.label.toLowerCase()}',
                orElse: () => 'загрузка…',
              ),
              style: TextStyle(fontSize: 11, color: c.gray),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _FilterButton(
              count: filters.activeCount,
              onTap: () => showFiltersSheet(context, ref),
            ),
          ),
        ],
      ),
      body: AsyncValueView<List<Product>>(
        value: results,
        loading: const SkeletonList(),
        onRetry: () => ref.invalidate(catalogResultsProvider(slug)),
        isEmpty: (d) => d.isEmpty,
        empty: const EmptyState(
          title: 'Ничего не нашлось',
          subtitle: 'Попробуйте убрать фильтры.',
          icon: Icons.search_off_rounded,
        ),
        data: (list) {
          // Спонсорские предложения — крупными карточками сверху.
          final sponsored = CatalogRepository.sponsoredFrom(list);
          return CustomScrollView(
            slivers: [
              if (sponsored.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final s = sponsored[i];
                        final supplier = s.offer.supplierName.isEmpty
                            ? 'поставщик'
                            : s.offer.supplierName;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ProductGridCard(
                            product: s.product,
                            featured: true,
                            badge: 'ПРОДВИГАЕТСЯ',
                            priceOverride: s.offer.price,
                            metaOverride: supplier,
                            onTap: () => s.offer.supplierId != null
                                ? context.push(Routes.supplier(s.offer.supplierId!))
                                : context.push(Routes.product(s.product.id)),
                          ),
                        );
                      },
                      childCount: sponsored.length,
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    16, sponsored.isNotEmpty ? 4 : 12, 16, 24),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 226,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => ProductGridCard(product: list[i]),
                    childCount: list.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: c.field,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: c.line)),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, size: 16, color: c.ink),
            const SizedBox(width: 6),
            Text('Фильтры${count > 0 ? ' · $count' : ''}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
