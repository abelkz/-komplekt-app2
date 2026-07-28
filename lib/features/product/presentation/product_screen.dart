import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/config/supabase_client.dart';
import '../../../core/providers/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/launchers.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/category_icons.dart';
import '../../catalog/domain/offer.dart';
import '../../catalog/domain/product.dart';
import '../../collections/presentation/collections_providers.dart';
import '../../collections/presentation/widgets/collection_picker.dart';
import '../../favorites/presentation/favorites_providers.dart';
import 'product_providers.dart';
import 'widgets/price_history_section.dart';
import 'widgets/reviews_section.dart';

/// Экран 5 — Карточка товара: фото, характеристики, сравнение цен,
/// отзывы и кнопки связи с продавцами.
class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  bool _viewLogged = false;
  RealtimeChannel? _priceChannel;

  @override
  void initState() {
    super.initState();
    _subscribePrices();
  }

  /// Подписка на изменения цен этого товара (Realtime) — цена обновится
  /// на экране без перезахода. В демо-режиме пропускаем.
  void _subscribePrices() {
    if (Env.demoMode) return;
    try {
      _priceChannel = supabase
          .channel('offers:${widget.productId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'offers',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'product_id',
              value: widget.productId,
            ),
            callback: (_) {
              if (mounted) ref.invalidate(productProvider(widget.productId));
            },
          )
          .subscribe();
    } catch (_) {/* realtime не критичен */}
  }

  @override
  void dispose() {
    final ch = _priceChannel;
    if (ch != null) {
      try {
        supabase.removeChannel(ch);
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productId = widget.productId;

    // Засчитываем просмотр поставщикам один раз, когда товар загрузился
    ref.listen(productProvider(productId), (_, next) {
      final p = next.valueOrNull;
      if (p != null && !_viewLogged) {
        _viewLogged = true;
        ref.read(eventsRepositoryProvider).logView(p);
      }
    });
    final isFav = ref.watch(favoriteIdsProvider
        .select((s) => s.valueOrNull?.contains(productId) ?? false));

    // «Паспорт образца» всегда тёмный — независимо от темы приложения.
    // Обёртка в тёмную тему разом переводит все дочерние виджеты
    // (шапку, предложения, отзывы) на кость по туши.
    return Theme(
      data: AppTheme.dark(),
      child: Builder(builder: (context) => _scaffold(context, productId, isFav)),
    );
  }

  Widget _scaffold(BuildContext context, String productId, bool isFav) {
    final c = context.colors;
    final product = ref.watch(productProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: Text('ПАСПОРТ ОБРАЗЦА',
            style: AppTypography.mono(
                size: 11, weight: FontWeight.w700, color: c.ink)),
        actions: [
          IconButton(
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? c.orange : c.ink,
            ),
            onPressed: () async {
              try {
                await ref.read(favoriteIdsProvider.notifier).toggle(productId);
              } catch (_) {
                _snack(context, 'Не сохранилось — проверьте связь');
              }
            },
          ),
        ],
      ),
      body: AsyncValueView<Product>(
        value: product,
        onRetry: () => ref.invalidate(productProvider(productId)),
        data: (p) => _ProductBody(product: p),
      ),
      bottomNavigationBar: product.maybeWhen(
        data: (p) => _AddToCollectionBar(product: p),
        orElse: () => null,
      ),
    );
  }
}

class _ProductBody extends StatelessWidget {
  const _ProductBody({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final offers = product.sortedOffers;
    final mn = product.minPrice ?? 0;

    final best = offers.isNotEmpty ? offers.first : null;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Hero(product: product),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Блок «лучшая цена + тренд за месяц»
              if (best != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ЛУЧШАЯ ЦЕНА',
                              style:
                                  AppTypography.sectionLabel(color: c.gray)),
                          const SizedBox(height: 4),
                          Text(Formatters.price(mn),
                              style: AppTypography.unbounded(
                                  size: 28, color: c.accent)),
                        ],
                      ),
                    ),
                    if (best.changePercent != null)
                      _TrendPill(pct: best.changePercent!),
                  ],
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 18, horizontal: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Text(
                    'Цена не указана — поставщики ещё не прислали прайс '
                    'на этот товар.',
                    style: TextStyle(fontSize: 13, color: c.gray, height: 1.35),
                  ),
                ),

              // Кнопки связи с лучшим поставщиком
              if (best != null) ...[
                const SizedBox(height: 16),
                _ContactButtons(product: product, offer: best),
              ],

              // Характеристики (если есть что показать)
              _SpecsCard(product: product),

              // Все предложения — шкала цен всех поставщиков
              if (offers.isNotEmpty) ...[
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text('ВСЕ ПРЕДЛОЖЕНИЯ — ${offers.length} ПОСТ.',
                          style: AppTypography.sectionLabel(color: c.gray)),
                    ),
                    if (offers.length > 1)
                      Text(
                        'Δ ${Formatters.price(offers.last.price - mn)}',
                        style: AppTypography.mono(size: 10, color: c.accent),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                for (int i = 0; i < offers.length; i++)
                  _OfferCard(
                    offer: offers[i],
                    minPrice: mn,
                    best: i == 0,
                    productId: product.id,
                    productName: product.name,
                  ),
              ],

              const SizedBox(height: 8),
              PriceHistorySection(productId: product.id),
              const SizedBox(height: 18),
              ReviewsSection(productId: product.id),
            ],
          ),
        ),
      ],
    );
  }
}

/// Крупное фото товара на всю ширину: рейтинг сверху, название и
/// подзаголовок поверх затемнения снизу — как в макете.
class _Hero extends StatelessWidget {
  const _Hero({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = product.primaryImageUrl;
    final bg = product.placeholderColor ?? c.field;
    final onBg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white24
        : Colors.black12;

    return SizedBox(
      height: 320,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null)
            CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
          else
            Container(
              color: bg,
              alignment: Alignment.center,
              child: Icon(CategoryIcons.of(product.categorySlug),
                  size: 72, color: onBg),
            ),
          // затемнение снизу под название
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
                stops: [0.4, 1],
              ),
            ),
          ),
          // плашка рейтинга
          if (product.rating > 0)
            Positioned(
              top: 12,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 14, color: AppColors.brandInk),
                    const SizedBox(width: 4),
                    Text(
                      'Рейтинг ${product.rating.toStringAsFixed(1)}',
                      style: AppTypography.sectionLabel(
                              color: AppColors.brandInk)
                          .copyWith(fontSize: 10, letterSpacing: 0.2),
                    ),
                  ],
                ),
              ),
            ),
          // название + подзаголовок
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.unbounded(size: 26, color: Colors.white),
                ),
                if (product.brand.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    product.brand,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferCard extends ConsumerWidget {
  const _OfferCard({
    required this.offer,
    required this.minPrice,
    required this.best,
    required this.productId,
    required this.productName,
  });

  final Offer offer;
  final double minPrice;
  final bool best;
  final String productId;
  final String productName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final diff = minPrice == 0 ? 0 : ((offer.price - minPrice) / minPrice * 100).round();

    // фиксируем обращение к поставщику + запускаем нужное действие
    void contact(Future<bool> Function() launch) {
      ref.read(eventsRepositoryProvider).logContact(productId, offer.supplierId);
      launch();
    }
    final barWidth = (100 - diff * 4).clamp(8, 100) / 100;

    // Карточка предложения: у лучшего — золотая рамка, остальные — обычная.
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(15, 14, 12, 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: best ? c.accent : c.line,
          width: best ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Имя ведёт в витрину поставщика: все его товары,
                        // контакты, годы на рынке, отзывы.
                        Flexible(
                          child: GestureDetector(
                            onTap: offer.supplierId == null
                                ? null
                                : () => context
                                    .push(Routes.supplier(offer.supplierId!)),
                            child: Text(offer.supplierName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    decoration: offer.supplierId == null
                                        ? null
                                        : TextDecoration.underline,
                                    decorationColor: c.gray)),
                          ),
                        ),
                        // Проверенная компания. Значок про документы,
                        // а не про оплату — и на порядок в шкале цен
                        // он не влияет: выше стоит тот, у кого дешевле.
                        if (offer.supplierVerified) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.verified, size: 15, color: c.green),
                        ],
                        if (best) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                                color: c.orange,
                                borderRadius: BorderRadius.circular(6)),
                            child: const Text('ЛУЧШАЯ ЦЕНА',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.brandInk)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${offer.city} · обновлено ${Formatters.relativeDate(offer.priceUpdatedAt)}',
                      style: TextStyle(fontSize: 11, color: c.faint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Formatters.price(offer.price),
                      style: AppTypography.unbounded(
                          size: best ? 17 : 14,
                          color: best ? c.accent : c.ink)),
                  // Изменение относительно прежней цены этого поставщика
                  if (offer.changePercent != null) ...[
                    Text(
                      offer.changePercent! < 0
                          ? '▼ ${offer.changePercent!.abs()}% · было ${Formatters.price(offer.prevPrice!)}'
                          : '▲ ${offer.changePercent}% · было ${Formatters.price(offer.prevPrice!)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: offer.changePercent! < 0 ? c.green : c.red,
                      ),
                    ),
                  ],
                  if (!best && diff > 0)
                    Text('+$diff% к мин.',
                        style: TextStyle(
                            fontSize: 11,
                            color: c.red,
                            fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 11),
          // Полоска относительной цены
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: barWidth.toDouble(),
              minHeight: 5,
              backgroundColor: c.field,
              valueColor:
                  AlwaysStoppedAnimation(best ? c.orange : c.line),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: offer.inStock
                ? _StatusBadge('✓ в наличии', c.green, c.greenSoft)
                : _StatusBadge('под заказ', c.red, c.redSoft),
          ),
          const SizedBox(height: 10),
          // Кнопки связи — переносом, чтобы на узких экранах не вылезали
          // за край (раньше был красный «overflow» и WhatsApp обрезался).
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (offer.phone != null)
                _MiniButton(
                  icon: Icons.call_outlined,
                  label: 'Звонок',
                  onTap: () => contact(() => Launchers.call(offer.phone!)),
                ),
              if (offer.whatsapp != null)
                _MiniButton(
                  icon: Icons.chat_outlined,
                  label: 'WhatsApp',
                  onTap: () => contact(() => Launchers.whatsapp(offer.whatsapp!,
                      text: 'Здравствуйте! Интересует «$productName»')),
                ),
              if (offer.website != null)
                _MiniButton(
                  icon: Icons.link_rounded,
                  label: 'Сайт',
                  onTap: () => contact(() => Launchers.website(offer.website!)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddToCollectionBar extends ConsumerWidget {
  const _AddToCollectionBar({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cols = ref.watch(collectionsProvider).valueOrNull ?? const [];
    final inCollection =
        cols.any((col) => col.items.any((i) => i.productId == product.id));
    // Одна подборка — кладём сразу; две и больше — спрашиваем, в какую
    final needPicker = cols.length > 1;
    final c = context.colors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: inCollection ? c.green : c.accent,
              foregroundColor:
                  inCollection ? Colors.white : AppColors.brandInk,
            ),
            icon: Icon(inCollection ? Icons.check : Icons.add, size: 20),
            label: Text(needPicker
                ? (inCollection ? 'В подборках — изменить' : 'Выбрать подборку')
                : (inCollection ? 'В комплекте' : 'В комплект +')),
            onPressed: () async {
              if (needPicker) {
                await showCollectionPicker(context, ref, product.id);
                return;
              }
              try {
                final name = await ref
                    .read(collectionsProvider.notifier)
                    .addToDefault(product.id);
                if (context.mounted) _snack(context, 'Добавлено в «$name»');
              } catch (_) {
                if (context.mounted) {
                  _snack(context, 'Не сохранилось — проверьте связь');
                }
              }
            },
          ),
        ),
      ),
    );
  }
}

/// Плашка тренда цены за месяц: рост — красным, снижение — зелёным.
class _TrendPill extends StatelessWidget {
  const _TrendPill({required this.pct});
  final num pct;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final down = pct < 0;
    final color = down ? c.green : c.red;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(down ? Icons.trending_down_rounded : Icons.trending_up_rounded,
            size: 16, color: color),
        const SizedBox(width: 4),
        Text('${down ? '−' : '+'}${pct.abs()}% за мес.',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

/// Три крупные кнопки связи с лучшим поставщиком (как в макете).
class _ContactButtons extends ConsumerWidget {
  const _ContactButtons({required this.product, required this.offer});
  final Product product;
  final Offer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    void contact(Future<bool> Function() launch) {
      ref.read(eventsRepositoryProvider).logContact(product.id, offer.supplierId);
      launch();
    }

    final buttons = <Widget>[
      if (offer.phone != null)
        _BigContact(
          icon: Icons.call_rounded,
          label: 'Позвонить',
          color: c.orange,
          onTap: () => contact(() => Launchers.call(offer.phone!)),
        ),
      if (offer.whatsapp != null)
        _BigContact(
          icon: Icons.chat_rounded,
          label: 'WhatsApp',
          color: const Color(0xFF25D366),
          onTap: () => contact(() => Launchers.whatsapp(offer.whatsapp!,
              text: 'Здравствуйте! Интересует «${product.name}»')),
        ),
      if (offer.website != null)
        _BigContact(
          icon: Icons.language_rounded,
          label: 'Сайт',
          color: c.orange,
          onTap: () => contact(() => Launchers.website(offer.website!)),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();

    final row = <Widget>[];
    for (var i = 0; i < buttons.length; i++) {
      if (i > 0) row.add(const SizedBox(width: 10));
      row.add(Expanded(child: buttons[i]));
    }
    return Row(children: row);
  }
}

class _BigContact extends StatelessWidget {
  const _BigContact({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(AppRadii.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: c.line),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Карточка характеристик из доступных полей товара.
class _SpecsCard extends StatelessWidget {
  const _SpecsCard({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <MapEntry<String, String>>[
      if (product.brand.isNotEmpty) MapEntry('Бренд', product.brand),
      if (product.sku.isNotEmpty) MapEntry('Артикул', product.sku),
      if (product.unit.isNotEmpty) MapEntry('Единица', product.unit),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Характеристики',
                  style: AppTypography.unbounded(size: 16, color: c.ink)),
              const SizedBox(height: 12),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(height: 18, thickness: 1, color: c.line),
                Row(
                  children: [
                    Text(rows[i].key,
                        style: TextStyle(fontSize: 13, color: c.gray)),
                    const Spacer(),
                    Flexible(
                      child: Text(rows[i].value,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: c.ink)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.text, this.fg, this.bg);
  final String text;
  final Color fg;
  final Color bg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
}

class _MiniButton extends StatelessWidget {
  const _MiniButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: c.paper,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: c.orange),
            const SizedBox(width: 5),
            Text(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
