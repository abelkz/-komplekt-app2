import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/category_icons.dart';
import '../../../favorites/presentation/favorites_providers.dart';
import '../../domain/product.dart';

/// Карточка-картинка товара в стиле «Industrial Noir»: крупное фото,
/// сердечко-избранное, название, число поставщиков, цена и скидка.
/// Используется в сетке каталога (2 колонки) и как крупная карточка (featured).
class ProductGridCard extends ConsumerWidget {
  const ProductGridCard({
    super.key,
    required this.product,
    this.featured = false,
    this.badge,
    this.onTap,
    this.priceOverride,
    this.metaOverride,
  });

  final Product product;
  final bool featured;

  /// Плашка в углу изображения: «Рекомендуем», «Новое» и т.п.
  final String? badge;

  /// Переопределение тапа (для спонсорских карточек — в витрину поставщика).
  final VoidCallback? onTap;

  /// Своя цена вместо минимальной (спонсор показывает цену своего поставщика).
  final double? priceOverride;

  /// Своя подпись вместо «N поставщиков» (напр. имя поставщика).
  final String? metaOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final fav = ref.watch(favoriteIdsProvider).valueOrNull ?? const {};
    final isFav = fav.contains(product.id);
    final mn = priceOverride ?? product.minPrice;
    // скидку показываем только для обычных карточек
    final saving = priceOverride == null ? product.savingPercent : 0;
    final imgHeight = featured ? 168.0 : 128.0;

    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => context.push(Routes.product(product.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Фото + сердечко + плашка ──
            SizedBox(
              height: imgHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CardImage(product: product),
                  // затемнение снизу — чтобы плашка/иконка читались
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black26],
                      ),
                    ),
                  ),
                  if (badge != null)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Text(
                          badge!,
                          style: AppTypography.sectionLabel(
                                  color: AppColors.brandInk)
                              .copyWith(fontSize: 10, letterSpacing: 0.3),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _HeartButton(
                      active: isFav,
                      onTap: () =>
                          ref.read(favoriteIdsProvider.notifier).toggle(product.id),
                    ),
                  ),
                ],
              ),
            ),
            // ── Текст ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: featured ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: featured ? 16 : 14,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metaOverride ?? _meta(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.gray),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          mn == null
                              ? Formatters.priceUnset
                              : Formatters.price(mn),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.unbounded(
                            size: featured ? 20 : 16,
                            color: mn == null ? c.faint : c.ink,
                          ),
                        ),
                      ),
                      if (saving > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '-$saving%',
                          style: AppTypography.mono(
                            size: 11,
                            weight: FontWeight.w700,
                            color: c.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _meta() {
    if (product.offersCount > 0) {
      return '${product.offersCount} ${_plural(product.offersCount)}';
    }
    if (product.sku.isNotEmpty) return 'арт. ${product.sku}';
    return 'нет предложений';
  }

  static String _plural(int n) {
    final m = n % 10, h = n % 100;
    if (m == 1 && h != 11) return 'поставщик';
    if (m >= 2 && m <= 4 && (h < 10 || h >= 20)) return 'поставщика';
    return 'поставщиков';
  }
}

/// Фото товара, заполняющее карточку (cover). Заглушка — цвет категории
/// с иконкой по центру.
class _CardImage extends StatelessWidget {
  const _CardImage({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = product.primaryImageUrl;
    final bg = product.placeholderColor ?? c.field;

    Widget placeholder() {
      final onBg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
          ? Colors.white24
          : Colors.black.withOpacity(0.18);
      return Container(
        color: bg,
        alignment: Alignment.center,
        child: Icon(CategoryIcons.of(product.categorySlug),
            size: 44, color: onBg),
      );
    }

    if (url == null) return placeholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: bg),
      errorWidget: (_, __, ___) => placeholder(),
    );
  }
}

/// Кнопка-сердечко поверх фото.
class _HeartButton extends StatelessWidget {
  const _HeartButton({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.black.withOpacity(0.35),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 18,
            color: active ? c.accent : Colors.white,
          ),
        ),
      ),
    );
  }
}
