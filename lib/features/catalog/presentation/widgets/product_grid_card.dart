import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/category_icons.dart';
import '../../../../core/widgets/sign_in_required.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../favorites/presentation/favorites_providers.dart';
import '../../domain/product.dart';

/// Карточка товара в сетке каталога: фото, бренд, название, цена от, число
/// продавцов и наличие.
///
/// Порядок строк не случайный. Бренд идёт над названием капсом и приглушённо —
/// в отделочных материалах марка отсеивает варианты быстрее, чем длинное
/// название, которое всё равно обрезается. Пара «цена от» + «N продавцов»
/// стоит рядом: это ровно тот вопрос, ради которого открывают приложение.
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

    // Наличие знаем только когда предложения приехали вместе с товаром —
    // в списке каталога их может не быть. Молчим, а не врём «под заказ».
    final hasOffers = product.offers.isNotEmpty;
    final inStock = hasOffers && product.offers.any((o) => o.inStock);

    return DecoratedBox(
      // Тонкая тёплая рамка вместо тени — карточка держит границу сама,
      // и сетка читается как таблица образцов, а не как стопка листочков.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: c.line),
      ),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
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
                    // затемнение снизу — чтобы плашка и сердечко читались
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
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(AppRadii.xs),
                          ),
                          child: Text(
                            badge!,
                            style: AppTypography.sectionLabel(
                                    color: AppColors.brandInk)
                                .copyWith(fontSize: 9, letterSpacing: 0.6),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _HeartButton(
                        active: isFav,
                        onTap: () {
                          // Каталог гость смотрит свободно, но избранное
                          // хранится за аккаунтом.
                          if (!ref.read(isSignedInProvider)) {
                            promptSignIn(
                                context, 'Войдите, чтобы следить за ценой');
                            return;
                          }
                          ref
                              .read(favoriteIdsProvider.notifier)
                              .toggle(product.id);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // Линейка отделяет фото от текста — та же роль, что у рамки:
              // граница, а не размытие.
              Container(height: 1, color: c.line),
              // ── Текст ──
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.brand.isNotEmpty) ...[
                      Text(
                        product.brand.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sectionLabel(color: c.faint)
                            .copyWith(fontSize: 10),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleMd(color: c.ink),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (mn != null)
                          Text('от ', style: AppTypography.bodySm(color: c.gray)),
                        Flexible(
                          child: Text(
                            mn == null
                                ? Formatters.priceUnset
                                : Formatters.price(mn),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mn == null
                                ? AppTypography.bodyMd(color: c.faint)
                                : AppTypography.priceMd(color: c.accent),
                          ),
                        ),
                        if (mn != null)
                          Text('/${product.unit}',
                              style: AppTypography.bodySm(color: c.gray)),
                        if (saving > 0) ...[
                          const SizedBox(width: 6),
                          Text('−$saving %',
                              style: AppTypography.data(color: c.green)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            metaOverride ?? _meta(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySm(color: c.faint),
                          ),
                        ),
                        if (hasOffers && metaOverride == null) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: inStock ? c.green : c.faint,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            inStock ? 'В наличии' : 'Под заказ',
                            style: AppTypography.bodySm(
                                color: inStock ? c.green : c.faint),
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
    if (m == 1 && h != 11) return 'продавец';
    if (m >= 2 && m <= 4 && (h < 10 || h >= 20)) return 'продавца';
    return 'продавцов';
  }
}

/// Фото товара, заполняющее карточку (cover). Заглушка — цвет категории
/// с иконкой по центру.
///
/// В сетке кадрирование уместно: тут выбирают из многих, и важнее ровный
/// ритм карточек. Целиком снимок показывается в карточке товара.
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
          : Colors.black.withValues(alpha: 0.18);
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
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 17,
            color: active ? c.accent : Colors.white,
          ),
        ),
      ),
    );
  }
}
