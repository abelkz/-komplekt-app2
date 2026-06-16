import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/category_icons.dart';
import '../../../core/widgets/tape_stripe.dart';
import '../../catalog/domain/category.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../notifications/presentation/notifications_providers.dart';

/// Экран 3 — Главная: поиск, категории, лента вдохновения.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _doSearch([String? value]) {
    final q = (value ?? _search.text).trim();
    if (q.isEmpty) return;
    ref.read(recentSearchesProvider.notifier).add(q);
    context.push('${Routes.search}?q=${Uri.encodeComponent(q)}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final categories = ref.watch(categoriesProvider);
    final feed = ref.watch(feedProvider);
    final recent = ref.watch(recentSearchesProvider);
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      body: Column(
        children: [
          const TapeStripe(),
          Expanded(
            child: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(feedProvider);
                  ref.invalidate(categoriesProvider);
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Шапка с переключателем темы
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('КОМПЛЕКТ',
                                          style: AppTypography.unbounded()),
                                      const SizedBox(height: 3),
                                      Text('цены поставщиков',
                                          style: TextStyle(
                                              fontSize: 12, color: c.gray)),
                                    ],
                                  ),
                                ),
                                Badge.count(
                                  count:
                                      ref.watch(unreadCountProvider).valueOrNull ??
                                          0,
                                  isLabelVisible: (ref
                                              .watch(unreadCountProvider)
                                              .valueOrNull ??
                                          0) >
                                      0,
                                  child: _IconButton(
                                    icon: Icons.notifications_none_rounded,
                                    onTap: () =>
                                        context.push(Routes.notifications),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _IconButton(
                                  icon: isDark
                                      ? Icons.light_mode_outlined
                                      : Icons.dark_mode_outlined,
                                  onTap: () => ref
                                      .read(settingsProvider.notifier)
                                      .toggleTheme(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _SearchBar(
                              controller: _search,
                              onSubmit: _doSearch,
                              onVisualSearch: () =>
                                  context.push(Routes.visualSearch),
                            ),
                            const SizedBox(height: 12),
                            // Кнопка карты поставщиков
                            _MapButton(onTap: () => context.push(Routes.map)),
                            const SizedBox(height: 6),
                            _SectionLabel('Категории'),
                          ],
                        ),
                      ),
                    ),

                    // Сетка категорий
                    SliverToBoxAdapter(
                      child: categories.when(
                        loading: () => const _GridSkeleton(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (list) => _CategoriesGrid(categories: list),
                      ),
                    ),

                    // Недавние поиски
                    if (recent.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel('Недавно искали'),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final r in recent)
                                    ActionChip(
                                      label: Text(r),
                                      onPressed: () => _doSearch(r),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: _SectionLabel('Лента вдохновения'),
                      ),
                    ),

                    // Masonry-лента (Pinterest)
                    feed.when(
                      loading: () => const SliverToBoxAdapter(
                          child: Padding(
                        padding: EdgeInsets.all(40),
                        child:
                            Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                      )),
                      error: (_, __) => const SliverToBoxAdapter(
                          child: SizedBox(height: 40)),
                      data: (products) => SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        sliver: SliverMasonryGrid.count(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childCount: products.length,
                          itemBuilder: (_, i) =>
                              _InspirationTile(product: products[i], index: i),
                        ),
                      ),
                    ),

                    // «Показать ещё» — догрузка следующей страницы ленты
                    if (ref.watch(feedProvider).hasValue &&
                        ref.read(feedProvider.notifier).hasMore)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          child: OutlinedButton(
                            onPressed: () =>
                                ref.read(feedProvider.notifier).loadMore(),
                            child: const Text('Показать ещё'),
                          ),
                        ),
                      )
                    else
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Поисковая строка ──
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onSubmit,
    required this.onVisualSearch,
  });
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final VoidCallback onVisualSearch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.only(left: 13, right: 6),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: c.faint),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmit,
              decoration: const InputDecoration(
                hintText: 'Название или артикул…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          // Поиск по фото — заглушка MVP (кнопка есть, логика позже)
          IconButton(
            tooltip: 'Поиск по фото интерьера',
            icon: Icon(Icons.camera_alt_outlined, color: c.gray, size: 20),
            onPressed: onVisualSearch,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: FilledButton(
              onPressed: () => onSubmit(controller.text),
              child: const Text('Найти'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          children: [
            Icon(Icons.map_outlined, color: c.orange, size: 20),
            const SizedBox(width: 10),
            Text('Поставщики на карте',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
            const Spacer(),
            Icon(Icons.chevron_right, color: c.faint),
          ],
        ),
      ),
    );
  }
}

class _CategoriesGrid extends StatelessWidget {
  const _CategoriesGrid({required this.categories});
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: categories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          childAspectRatio: 0.86,
        ),
        itemBuilder: (_, i) => _CategoryTile(category: categories[i]),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: () => context.push(Routes.catalog(category.slug),
          extra: category.name),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CategoryIcons.of(category.slug), color: c.orange, size: 22),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(category.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, height: 1.2)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspirationTile extends StatelessWidget {
  const _InspirationTile({required this.product, required this.index});
  final Product product;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Разная высота для эффекта masonry (Pinterest)
    final height = 150.0 + (index % 4) * 34;
    final bg = product.placeholderColor ?? c.field;
    final onBg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white
        : c.ink;
    final mn = product.minPrice;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: () => context.push(Routes.product(product.id)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          height: height,
          color: bg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Icon(CategoryIcons.of(product.categorySlug),
                    size: 40, color: onBg.withOpacity(0.35)),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: onBg,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.25)),
                    if (mn != null)
                      Text('от ${Formatters.price(mn)}',
                          style: TextStyle(
                              color: onBg.withOpacity(0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: context.colors.faint)),
      );
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: c.field, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: c.ink),
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
}
