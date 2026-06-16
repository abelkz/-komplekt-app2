import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/skeletons.dart';
import '../domain/product.dart';
import 'catalog_providers.dart';
import 'widgets/filters_sheet.dart';
import 'widgets/product_card.dart';

/// Результаты поиска по строке запроса (тот же UI, что и каталог).
class SearchResultsScreen extends ConsumerWidget {
  const SearchResultsScreen({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final results = ref.watch(searchResultsProvider(query));
    final filters = ref.watch(filtersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('«$query»',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(
              results.maybeWhen(
                data: (d) => '${d.length} товаров',
                orElse: () => 'поиск…',
              ),
              style: TextStyle(fontSize: 11, color: c.gray),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => showFiltersSheet(context, ref),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: c.field, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 16, color: c.ink),
                    const SizedBox(width: 6),
                    Text(
                        'Фильтры${filters.activeCount > 0 ? ' · ${filters.activeCount}' : ''}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: AsyncValueView<List<Product>>(
        value: results,
        loading: const SkeletonList(),
        onRetry: () => ref.invalidate(searchResultsProvider(query)),
        isEmpty: (d) => d.isEmpty,
        empty: const EmptyState(
          title: 'Ничего не нашлось',
          subtitle: 'Попробуйте артикул производителя или уберите фильтры.',
          icon: Icons.search_off_rounded,
        ),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 11),
          itemBuilder: (_, i) => ProductCard(product: list[i]),
        ),
      ),
    );
  }
}
