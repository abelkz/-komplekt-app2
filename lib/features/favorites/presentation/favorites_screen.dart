import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/sign_in_required.dart';
import '../../../core/widgets/skeletons.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/domain/category.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../catalog/presentation/widgets/product_thumb.dart';
import '../../collections/presentation/collections_providers.dart';
import 'favorites_providers.dart';

/// Экран 7 — Избранное: список наблюдения за ценами.
///
/// Не сетка, как в каталоге: там выбирают из многих и важна картинка, а здесь
/// следят за своими и важно, что изменилось. Поэтому строки, в каждой — цена
/// со старой, наличие и поставщик, а внизу итог по всему списку.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  /// null — «Все». Иначе либо служебный фильтр, либо slug категории.
  String? _filter;
  bool _building = false;

  static const _cheaper = '#cheaper';
  static const _inStock = '#instock';

  @override
  Widget build(BuildContext context) {
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

    final c = context.colors;
    final favs = ref.watch(favoriteProductsProvider);

    // Снижения считает база (RPC price_drops). Берём только пересечение с
    // избранным: человеку важно, подешевело ли именно у него.
    final drops = {
      for (final d in ref.watch(priceDropsProvider).valueOrNull ?? const [])
        d.product.id: d,
    };

    return Scaffold(
      body: SafeArea(
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
          data: (all) {
            final cheaper = all.where((p) => drops.containsKey(p.id)).toList();
            final inStock =
                all.where((p) => p.offers.any((o) => o.inStock)).toList();

            // Категории, которые реально есть в избранном: чипов не должно
            // быть больше, чем разделов у человека на руках. Названия берём
            // из справочника — в товаре лежит только slug.
            final names = {
              for (final cat in ref.watch(categoriesProvider).valueOrNull ??
                  const <Category>[])
                cat.slug: cat.name,
            };
            final cats = <String, String>{};
            for (final p in all) {
              final slug = p.categorySlug;
              if (slug != null && slug.isNotEmpty) {
                cats.putIfAbsent(slug, () => names[slug] ?? slug);
              }
            }

            final list = switch (_filter) {
              null => all,
              _cheaper => cheaper,
              _inStock => inStock,
              final slug => all.where((p) => p.categorySlug == slug).toList(),
            };
            final total =
                all.map((p) => p.minPrice ?? 0).fold<double>(0, (a, b) => a + b);

            return Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(count: all.length),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(favoriteProductsProvider);
                          ref.invalidate(priceDropsProvider);
                        },
                        child: ListView(
                          // Снизу место под плавающую панель, иначе она
                          // накроет последнюю карточку.
                          padding: const EdgeInsets.fromLTRB(0, 12, 0, 96),
                          children: [
                            if (cheaper.isNotEmpty) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: _DropsBanner(
                                  count: cheaper.length,
                                  maxPercent: cheaper
                                      .map((p) => drops[p.id]!.percent)
                                      .reduce((a, b) => a > b ? a : b),
                                  onShow: () =>
                                      setState(() => _filter = _cheaper),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            _Filters(
                              active: _filter,
                              all: all.length,
                              cheaper: cheaper.length,
                              inStock: inStock.length,
                              categories: cats,
                              onPick: (f) => setState(() => _filter = f),
                            ),
                            const SizedBox(height: 12),
                            for (final p in list)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                child: _FavoriteRow(
                                  product: p,
                                  percent: drops[p.id]?.percent,
                                  oldPrice: drops[p.id]?.oldPrice,
                                ),
                              ),
                            if (list.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                                child: Text(
                                  'В этом фильтре ничего нет.',
                                  style: AppTypography.bodyMd(color: c.gray),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 12,
                  child: _TransferBar(
                    count: all.length,
                    total: total,
                    busy: _building,
                    onBuild: () => _buildSpec(all),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Собрать смету из всего избранного: создаём подборку и складываем в неё
  /// все позиции. Количества человек правит уже в «Подборках» — там для
  /// этого есть счётчики и итог.
  Future<void> _buildSpec(List<Product> all) async {
    if (all.isEmpty || _building) return;
    setState(() => _building = true);
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(collectionsProvider.notifier);
    final now = DateTime.now();
    final name = 'Смета от ${now.day.toString().padLeft(2, '0')}.'
        '${now.month.toString().padLeft(2, '0')}';
    try {
      final id = await notifier.createWith(name, all.first.id);
      for (final p in all.skip(1)) {
        await notifier.addTo(id, p.id);
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Смета «$name» собрана'),
        action: SnackBarAction(
          label: 'Открыть',
          onPressed: () => context.go(Routes.collections),
        ),
      ));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Не удалось собрать смету')));
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Избранное', style: AppTypography.headlineSm(color: c.ink)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: c.field,
              borderRadius: BorderRadius.circular(AppRadii.xs),
            ),
            child: Text('$count поз.',
                style: AppTypography.data(color: c.faint)),
          ),
          const Spacer(),
          _SquareButton(
            icon: Icons.search_rounded,
            tooltip: 'Поиск по каталогу',
            onTap: () => context.push(Routes.search),
          ),
        ],
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 20, color: c.gray),
          ),
        ),
      ),
    );
  }
}

/// Плашка «подешевели N позиций» — главная причина держать избранное:
/// товар отмечают не чтобы любоваться, а чтобы поймать снижение.
class _DropsBanner extends StatelessWidget {
  const _DropsBanner({
    required this.count,
    required this.maxPercent,
    required this.onShow,
  });

  final int count;
  final int maxPercent;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.greenSoft,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: c.green.withValues(alpha: 0.35)),
            ),
            child: Icon(Icons.trending_down_rounded, size: 20, color: c.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Подешевели $count ${_positions(count)}',
                          style: AppTypography.titleMd(color: c.ink)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.greenSoft,
                        borderRadius: BorderRadius.circular(AppRadii.xs),
                      ),
                      child: Text('−$maxPercent % макс.',
                          style: AppTypography.data(color: c.green)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Из тех, за чем вы следите. Сравнение с началом месяца.',
                  style: AppTypography.bodySm(color: c.faint),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onShow,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Фильтровать со скидкой',
                          style: AppTypography.data(color: c.accent)),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          size: 14, color: c.accent),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _positions(int n) {
    final m = n % 10, h = n % 100;
    if (m == 1 && h != 11) return 'позиция';
    if (m >= 2 && m <= 4 && (h < 10 || h >= 20)) return 'позиции';
    return 'позиций';
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.active,
    required this.all,
    required this.cheaper,
    required this.inStock,
    required this.categories,
    required this.onPick,
  });

  final String? active;
  final int all;
  final int cheaper;
  final int inStock;
  final Map<String, String> categories;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _Chip(
            label: 'Все',
            count: all,
            active: active == null,
            onTap: () => onPick(null),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Снизилась цена',
            count: cheaper,
            active: active == _FavoritesScreenState._cheaper,
            dot: c.green,
            countColor: c.green,
            onTap: () => onPick(_FavoritesScreenState._cheaper),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'В наличии',
            count: inStock,
            active: active == _FavoritesScreenState._inStock,
            onTap: () => onPick(_FavoritesScreenState._inStock),
          ),
          for (final e in categories.entries) ...[
            const SizedBox(width: 8),
            _Chip(
              label: e.value,
              active: active == e.key,
              onTap: () => onPick(e.key),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
    this.dot,
    this.countColor,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? count;
  final Color? dot;
  final Color? countColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      // Активный чип — рамкой и цветом текста, а не заливкой: жёлтый в этой
      // системе означает действие, а фильтр это состояние.
      color: c.card,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: active ? c.accent : c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: AppTypography.bodySm(
                      color: active ? c.accent : c.gray)),
              if (count != null) ...[
                const SizedBox(width: 5),
                Text('($count)',
                    style: AppTypography.data(
                        color: countColor ?? (active ? c.accent : c.faint))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка избранного.
class _FavoriteRow extends ConsumerWidget {
  const _FavoriteRow({required this.product, this.percent, this.oldPrice});

  final Product product;
  final int? percent;
  final double? oldPrice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final p = product;
    final best = p.bestOffer;
    final inStock = p.offers.any((o) => o.inStock);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => context.push(Routes.product(p.id)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          border: Border.all(color: c.line),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ProductThumb(product: p, size: 96),
                      ),
                      if (percent != null)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: c.greenSoft,
                              borderRadius: BorderRadius.circular(AppRadii.xs),
                              border: Border.all(
                                  color: c.green.withValues(alpha: 0.4)),
                            ),
                            child: Text('−$percent %',
                                style: AppTypography.data(color: c.green)
                                    .copyWith(fontSize: 10)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                [
                                  if (p.brand.isNotEmpty) p.brand.toUpperCase(),
                                  if (p.sku.isNotEmpty) p.sku,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    AppTypography.sectionLabel(color: c.faint)
                                        .copyWith(fontSize: 10),
                              ),
                            ),
                            // Закладка залита: товар уже под наблюдением,
                            // действие здесь — снять, а не добавить.
                            GestureDetector(
                              onTap: () => ref
                                  .read(favoriteIdsProvider.notifier)
                                  .toggle(p.id),
                              child: Icon(Icons.bookmark_rounded,
                                  size: 18, color: c.accent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleMd(color: c.ink),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                p.minPrice == null
                                    ? Formatters.priceUnset
                                    : Formatters.price(p.minPrice!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.priceLg(color: c.accent),
                              ),
                            ),
                            Text('/${p.unit}',
                                style: AppTypography.bodySm(color: c.gray)),
                            const SizedBox(width: 8),
                            // Если цена падала — показываем старую
                            // зачёркнутой; если нет — сколько продавцов.
                            if (oldPrice != null)
                              Text(
                                Formatters.price(oldPrice!),
                                style: AppTypography.bodySm(color: c.faint)
                                    .copyWith(
                                        decoration: TextDecoration.lineThrough),
                              )
                            else
                              Text('${p.offersCount} ${_sellers(p.offersCount)}',
                                  style: AppTypography.data(color: c.faint)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                best == null
                                    ? 'нет предложений'
                                    : '${best.supplierName} · ${best.city}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodySm(color: c.faint),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              inStock ? '● В наличии' : '○ Под заказ',
                              style: AppTypography.bodySm(
                                  color: inStock ? c.green : c.gray),
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
          // Подвал карточки на подложке потемнее — служебная полоса,
          // отделённая от содержимого линейкой.
          Container(
            decoration: BoxDecoration(
              color: c.paper,
              border: Border(top: BorderSide(color: c.line)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(
              children: [
                Icon(Icons.update_rounded, size: 15, color: c.faint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    best?.priceUpdatedAt == null
                        ? 'цена без изменений'
                        : 'цена обновлена '
                            '${Formatters.relativeDate(best!.priceUpdatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.data(color: c.faint),
                  ),
                ),
                _AddToSpecButton(product: p),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _sellers(int n) {
    final m = n % 10, h = n % 100;
    if (m == 1 && h != 11) return 'продавец';
    if (m >= 2 && m <= 4 && (h < 10 || h >= 20)) return 'продавца';
    return 'продавцов';
  }
}

class _AddToSpecButton extends ConsumerWidget {
  const _AddToSpecButton({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            final name = await ref
                .read(collectionsProvider.notifier)
                .addToDefault(product.id);
            messenger
                .showSnackBar(SnackBar(content: Text('Добавлено в «$name»')));
          } catch (_) {
            messenger.showSnackBar(
                const SnackBar(content: Text('Не удалось добавить')));
          }
        },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 15, color: c.accent),
              const SizedBox(width: 4),
              Text('В смету', style: AppTypography.bodySm(color: c.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плавающая панель: сколько позиций под наблюдением, ориентир по сумме и
/// сборка сметы одним действием.
class _TransferBar extends StatelessWidget {
  const _TransferBar({
    required this.count,
    required this.total,
    required this.busy,
    required this.onBuild,
  });

  final int count;
  final double total;
  final bool busy;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.ink.withValues(alpha: 0.06), c.card),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Выбрано $count ${_positions(count)}',
                    style: AppTypography.data(color: c.ink)),
                const SizedBox(height: 3),
                Text(
                  'ОРИЕНТИР: ${Formatters.priceOr(total, fallback: '—')}',
                  style: AppTypography.sectionLabel(color: c.faint)
                      .copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: AppColors.brandInk,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
            ),
            icon: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long_rounded, size: 16),
            label: Text(busy ? 'Собираю…' : 'Сформировать смету',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onPressed: busy || count == 0 ? null : onBuild,
          ),
        ],
      ),
    );
  }

  static String _positions(int n) {
    final m = n % 10, h = n % 100;
    if (m == 1 && h != 11) return 'позиция';
    if (m >= 2 && m <= 4 && (h < 10 || h >= 20)) return 'позиции';
    return 'позиций';
  }
}
