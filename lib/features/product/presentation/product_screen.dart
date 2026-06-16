import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/config/supabase_client.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/launchers.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/category_icons.dart';
import '../../catalog/domain/offer.dart';
import '../../catalog/domain/product.dart';
import '../../collections/presentation/collections_providers.dart';
import '../../favorites/presentation/favorites_providers.dart';
import 'product_providers.dart';
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
    final c = context.colors;
    final product = ref.watch(productProvider(productId));

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сравнение цен',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _Hero(product: product),
        const SizedBox(height: 16),
        Text(product.name,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.3)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (product.sku.isNotEmpty) _MetaChip('арт. ${product.sku}'),
            if (product.brand.isNotEmpty) _MetaChip(product.brand),
            _MetaChip('цена за ${product.unit}'),
            if (product.rating > 0)
              _MetaChip('★ ${product.rating.toStringAsFixed(1)}'),
          ],
        ),
        const SizedBox(height: 18),
        Text('ПРЕДЛОЖЕНИЯ ПОСТАВЩИКОВ',
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: c.faint)),
        const SizedBox(height: 10),
        for (int i = 0; i < offers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _OfferCard(
              offer: offers[i],
              minPrice: mn,
              best: i == 0,
              productId: product.id,
              productName: product.name,
            ),
          ),
        const SizedBox(height: 18),
        ReviewsSection(productId: product.id),
      ],
    );
  }
}

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

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: url != null
            ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
            : Container(
                color: bg,
                alignment: Alignment.center,
                child: Icon(CategoryIcons.of(product.categorySlug),
                    size: 64, color: onBg),
              ),
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

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(
            color: best ? c.orange : c.line, width: best ? 1.5 : 1),
        borderRadius: BorderRadius.circular(AppRadii.md),
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
                        Flexible(
                          child: Text(offer.supplierName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
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
                                    color: Colors.white)),
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
                      style: TextStyle(
                          fontSize: best ? 17 : 15,
                          fontWeight: FontWeight.w800,
                          color: c.ink)),
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
          Row(
            children: [
              offer.inStock
                  ? _StatusBadge('✓ в наличии', c.green, c.greenSoft)
                  : _StatusBadge('под заказ', c.red, c.redSoft),
              const Spacer(),
              if (offer.phone != null)
                _MiniButton(
                  icon: Icons.call_outlined,
                  label: 'Звонок',
                  onTap: () => contact(() => Launchers.call(offer.phone!)),
                ),
              if (offer.whatsapp != null) ...[
                const SizedBox(width: 8),
                _MiniButton(
                  icon: Icons.chat_outlined,
                  label: 'WhatsApp',
                  onTap: () => contact(() => Launchers.whatsapp(offer.whatsapp!,
                      text: 'Здравствуйте! Интересует «$productName»')),
                ),
              ],
              if (offer.website != null) ...[
                const SizedBox(width: 8),
                _MiniButton(
                  icon: Icons.link_rounded,
                  label: 'Сайт',
                  onTap: () => contact(() => Launchers.website(offer.website!)),
                ),
              ],
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
    final inCollection = ref.watch(collectionsProvider).maybeWhen(
          data: (cols) =>
              cols.any((c) => c.items.any((i) => i.productId == product.id)),
          orElse: () => false,
        );
    final c = context.colors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: inCollection ? c.green : c.ink,
              foregroundColor: Colors.white,
            ),
            icon: Icon(inCollection ? Icons.check : Icons.add, size: 20),
            label: Text(inCollection
                ? 'В подборке проекта'
                : 'Добавить в подборку проекта'),
            onPressed: () async {
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

class _MetaChip extends StatelessWidget {
  const _MetaChip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: c.field, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: c.gray)),
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
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration:
            BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Icon(icon, size: 15, color: c.ink),
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
