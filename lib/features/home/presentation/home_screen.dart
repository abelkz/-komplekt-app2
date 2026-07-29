import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/onboarding/feature_tour.dart';
import '../../../core/providers/providers.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/category_icons.dart';
import '../../catalog/domain/category.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../notifications/presentation/notifications_providers.dart';

/// Экран 3 — Главная: поиск, bento-категории, горячие предложения.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTour());
  }

  Future<void> _maybeShowTour() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    FeatureTour.maybeShow(
      context,
      store: ref.read(localStoreProvider),
      id: 'home',
      steps: [
        TourStep(
          key: TourKeys.search,
          title: 'Поиск материалов',
          text: 'Введите название, артикул или марку — покажем все '
              'предложения поставщиков с ценами. Значок камеры — поиск по фото.',
        ),
        TourStep(
          key: TourKeys.map,
          title: 'Поставщики на карте',
          text: 'Кто торгует рядом с вами: адреса, расстояние и контакты.',
        ),
        TourStep(
          key: TourKeys.bell,
          title: 'Уведомления о ценах',
          text: 'Добавьте товар в избранное — сообщим, когда цена снизится.',
        ),
        TourStep(
          key: TourKeys.navBar,
          title: 'Разделы приложения',
          text: 'Поиск, Избранное и Комплекты объектов. В Профиле можно '
              'стать поставщиком и разместить свои товары.',
        ),
      ],
    );
  }

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
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final isDark = themeMode == ThemeMode.dark;
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(feedProvider);
            ref.invalidate(categoriesProvider);
          },
          child: CustomScrollView(
            slivers: [
              // ── Шапка: логотип + колокол + тема ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Icon(Icons.architecture_rounded,
                          color: c.orange, size: 24),
                      const SizedBox(width: 8),
                      Text('Komplekt',
                          style: AppTypography.unbounded(
                              size: 20, color: c.orange)),
                      const Spacer(),
                      KeyedSubtree(
                        key: TourKeys.bell,
                        child: Badge.count(
                          count: unread,
                          isLabelVisible: unread > 0,
                          child: _IconButton(
                            icon: Icons.notifications_none_rounded,
                            onTap: () => context.push(Routes.notifications),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _IconButton(
                        icon: isDark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        onTap: () =>
                            ref.read(settingsProvider.notifier).toggleTheme(),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Заголовок + поиск + карта ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Сегодня '),
                            TextSpan(
                                text: 'дешевле',
                                style: TextStyle(color: c.orange)),
                            const TextSpan(text: ' здесь'),
                          ],
                        ),
                        style: AppTypography.unbounded(size: 30, color: c.ink),
                      ),
                      const SizedBox(height: 18),
                      KeyedSubtree(
                        key: TourKeys.search,
                        child: _SearchBar(
                          controller: _search,
                          onSubmit: _doSearch,
                          onVisualSearch: () =>
                              context.push(Routes.visualSearch),
                        ),
                      ),
                      const SizedBox(height: 12),
                      KeyedSubtree(
                        key: TourKeys.map,
                        child:
                            _MapButton(onTap: () => context.push(Routes.map)),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Категории (bento) ──
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Категории',
                  action: 'Все',
                  onAction: null,
                ),
              ),
              SliverToBoxAdapter(
                child: categories.when(
                  loading: () => const _GridSkeleton(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (list) => _CategoriesBento(categories: list),
                ),
              ),

              // ── Горячие предложения ──
              SliverToBoxAdapter(
                child: _SectionHeader(title: 'Горячие предложения', tag: 'SALE'),
              ),
              SliverToBoxAdapter(
                child: feed.when(
                  loading: () => const SizedBox(
                    height: 190,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5)),
                  ),
                  error: (_, __) => const SizedBox(height: 8),
                  data: (products) => _HotDealsRow(products: products),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Поисковая строка (пилюля) ──
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
      padding: const EdgeInsets.only(left: 16, right: 6),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(999),
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
                hintText: 'Поиск материалов…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Поиск по фото интерьера',
            icon: Icon(Icons.photo_camera_outlined, color: c.gray, size: 22),
            onPressed: onVisualSearch,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, color: c.orange, size: 20),
            const SizedBox(width: 10),
            Text('Поставщики на карте',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
          ],
        ),
      ),
    );
  }
}

// ── Bento-сетка категорий: крупная плитка + 2 колонки ──
class _CategoriesBento extends StatelessWidget {
  const _CategoriesBento({required this.categories});
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final featured = categories.first;
    final rest = categories.skip(1).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        children: [
          _FeaturedCategoryTile(category: featured),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rest.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 92,
            ),
            itemBuilder: (_, i) => _CategoryTileSmall(category: rest[i]),
          ),
        ],
      ),
    );
  }
}

class _FeaturedCategoryTile extends StatelessWidget {
  const _FeaturedCategoryTile({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      clipBehavior: Clip.antiAlias,
      color: c.card,
      child: InkWell(
        onTap: () => context.push(Routes.catalog(category.slug),
            extra: category.name),
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: c.line),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.card, Color.lerp(c.card, Colors.black, 0.5)!],
            ),
          ),
          child: Stack(
            children: [
              // крупная иконка-водяной знак
              Positioned(
                right: -10,
                bottom: -10,
                child: Icon(CategoryIcons.of(category.slug),
                    size: 128, color: c.orange.withOpacity(0.12)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.orange.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Icon(CategoryIcons.of(category.slug),
                          color: c.orange, size: 24),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.name,
                            style: AppTypography.unbounded(
                                size: 20, color: c.ink)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text('Смотреть все',
                                style: AppTypography.sectionLabel(
                                    color: c.orange)),
                            Icon(Icons.arrow_forward_rounded,
                                size: 14, color: c.orange),
                          ],
                        ),
                      ],
                    ),
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

class _CategoryTileSmall extends StatelessWidget {
  const _CategoryTileSmall({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(AppRadii.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.catalog(category.slug),
            extra: category.name),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Icon(CategoryIcons.of(category.slug), color: c.orange, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(category.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, height: 1.1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Горячие предложения: горизонтальный ряд карточек ──
class _HotDealsRow extends StatelessWidget {
  const _HotDealsRow({required this.products});
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox(height: 8);
    // сначала — со скидкой, затем остальные
    final sorted = [...products]
      ..sort((a, b) => b.savingPercent.compareTo(a.savingPercent));
    final list = sorted.take(10).toList();

    return SizedBox(
      height: 194,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _HotDealCard(product: list[i]),
      ),
    );
  }
}

class _HotDealCard extends StatelessWidget {
  const _HotDealCard({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = product.primaryImageUrl;
    final bg = product.placeholderColor ?? c.field;
    final mn = product.minPrice;
    final saving = product.savingPercent;

    return SizedBox(
      width: 168,
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(Routes.product(product.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 108,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url != null)
                      CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: bg),
                        errorWidget: (_, __, ___) => _ph(bg),
                      )
                    else
                      _ph(bg),
                    if (saving > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: c.red,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('-$saving%',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                        mn == null
                            ? Formatters.priceUnset
                            : Formatters.price(mn),
                        style: AppTypography.unbounded(
                            size: 15, color: mn == null ? c.faint : c.orange)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ph(Color bg) => Builder(builder: (context) {
        final onBg =
            ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
                ? Colors.white24
                : Colors.black.withOpacity(0.18);
        return Container(
          color: bg,
          alignment: Alignment.center,
          child: Icon(CategoryIcons.of(product.categorySlug),
              size: 36, color: onBg),
        );
      });
}

// ── Заголовок раздела ──
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.title, this.action, this.onAction, this.tag});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
      child: Row(
        children: [
          Text(title,
              style: AppTypography.unbounded(size: 17, color: c.ink)),
          const SizedBox(width: 8),
          if (tag != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: c.orange,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Text(tag!,
                  style: AppTypography.sectionLabel(color: AppColors.brandInk)
                      .copyWith(fontSize: 9)),
            ),
          const Spacer(),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action!,
                  style: AppTypography.sectionLabel(color: c.orange)),
            ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: c.card,
            shape: BoxShape.circle,
            border: Border.all(color: c.line)),
        child: Icon(icon, size: 20, color: c.ink),
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
