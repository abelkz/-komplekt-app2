import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/analytics/analytics.dart';
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
import '../../../core/widgets/sign_in_required.dart';
import '../../auth/presentation/auth_providers.dart';
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
        // Статистика поставщика считает просмотры по каждому его предложению,
        // а это — событие продукта: какие товары вообще открывают.
        Analytics.log(Analytics.productView, {
          'product_id': p.id,
          'category': p.categorySlug,
          'offers': p.offers.length,
        });
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
              // Избранное живёт за аккаунтом — гостю предлагаем войти,
              // а не показываем невнятную ошибку сохранения.
              if (!ref.read(isSignedInProvider)) {
                promptSignIn(context, 'Войдите, чтобы следить за ценой');
                return;
              }
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
              // Тренд цены за месяц. Самой цены здесь больше нет: она
              // переехала в нижнюю панель, где видна на всей длине экрана,
              // а метку «лучшее» теперь несёт строка в таблице цен —
              // раньше одно и то же было написано трижды.
              if (best != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: best.changePercent == null
                      ? const SizedBox.shrink()
                      : _TrendPill(pct: best.changePercent!),
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

              // Цены поставщиков — ради этого блока приложение и существует
              if (offers.isNotEmpty) ...[
                const SizedBox(height: 22),
                _PriceTable(product: product, offers: offers, minPrice: mn),
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

/// Крупное фото товара на всю ширину: листалка по галерее, тап — полный
/// экран с зумом. Рейтинг сверху, название и подзаголовок поверх затемнения
/// снизу — как в макете.
///
/// Раньше показывалось одно фото с `BoxFit.cover`: товар обрезался по краям,
/// а градиент до `black87` съедал нижние 60% снимка. Остальные фото из
/// `product_images` приезжали в запросе и не показывались вообще. Для
/// маркетплейса материалов фактура — половина решения о покупке, поэтому
/// снимок показываем целиком (`contain`) и даём разглядеть вблизи.
class _Hero extends StatefulWidget {
  const _Hero({required this.product});
  final Product product;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Полноэкранный просмотр открываем в корневом навигаторе, чтобы он лёг
  /// поверх нижней навигации, а не внутри вкладки.
  void _openViewer(List<String> urls, int start) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _PhotoViewer(urls: urls, initial: start),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final product = widget.product;
    final urls = product.galleryUrls;
    final bg = product.placeholderColor ?? c.field;
    final onBg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white24
        : Colors.black12;

    return SizedBox(
      height: 360,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Фон под вписанным фото: у снимка своя пропорция, и по бокам
          // остаются поля — пусть они будут цветом товара, а не чёрным.
          ColoredBox(color: bg),
          if (urls.isEmpty)
            Center(
              child: Icon(CategoryIcons.of(product.categorySlug),
                  size: 72, color: onBg),
            )
          else
            PageView.builder(
              controller: _pages,
              itemCount: urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _openViewer(urls, i),
                child:
                    CachedNetworkImage(imageUrl: urls[i], fit: BoxFit.contain),
              ),
            ),
          // Затемнение снизу под название — короче и слабее прежнего:
          // его задача сделать читаемым текст, а не прятать товар.
          // IgnorePointer обязателен, иначе плёнка съедает свайпы по фото.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                  stops: [0.68, 1],
                ),
              ),
            ),
          ),
          // Счётчик кадров вместо точек: фотографий у прайсовых товаров
          // бывает и десяток, точки в такой ряд не помещаются.
          if (urls.length > 1)
            Positioned(
              top: 12,
              right: 16,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Text(
                    '${_index + 1} / ${urls.length}',
                    style: AppTypography.mono(
                        size: 11,
                        weight: FontWeight.w700,
                        color: Colors.white),
                  ),
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

/// Полноэкранный просмотр фото: свайп между кадрами, щипок для зума.
///
/// Нужен именно отдельный экран: в карточке фото ограничено по высоте, а у
/// отделочных материалов решение принимают по фактуре — её надо разглядеть.
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.initial});

  final List<String> urls;
  final int initial;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                // 1 — фото вписано целиком, 4 — видно зерно и фактуру.
                // Больше не даём: у прайсовых снимков не та детализация.
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.urls[i],
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (widget.urls.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: Text(
                    '${_index + 1} / ${widget.urls.length}',
                    style: AppTypography.mono(
                        size: 12,
                        weight: FontWeight.w700,
                        color: Colors.white70),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ступень поверхности выше карточки — в макете это `surface-container-high`
/// (#282A2A). Отдельного токена в палитре нет, поэтому подмешиваем текстовый
/// цвет: работает и в тёмной теме, и в светлой, без новых полей в AppColors.
Color _raised(AppColors c) =>
    Color.alphaBlend(c.ink.withValues(alpha: 0.06), c.card);

/// Таблица цен поставщиков — ядро карточки товара.
///
/// Раньше это был список карточек: у каждой своя рамка, своя полоска-индикатор
/// и свои кнопки. Сравнивать так нельзя — цифры стоят на разных позициях, и
/// глаз ищет минимум заново в каждой строке. Теперь это одна таблица с
/// фиксированными колонками: цены выровнены по правому краю моноширинным
/// шрифтом с табличными цифрами, разница с минимумом подписана в процентах.
class _PriceTable extends StatelessWidget {
  const _PriceTable({
    required this.product,
    required this.offers,
    required this.minPrice,
  });

  final Product product;
  final List<Offer> offers;
  final double minPrice;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Самая свежая правка цены по всем предложениям: человеку важно знать,
    // насколько таблица вообще актуальна.
    final updated = offers
        .map((o) => o.priceUpdatedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Жёлтая засечка у заголовка — метка раздела из макета.
            Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('ЦЕНЫ ПОСТАВЩИКОВ',
                  style: AppTypography.sectionLabel(color: c.ink)),
            ),
            if (updated != null)
              Text('Обновлено ${Formatters.relativeDate(updated)}',
                  style: AppTypography.data(color: c.faint)),
          ],
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: c.line),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Column(
              children: [
                const _PriceTableHeader(),
                for (int i = 0; i < offers.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: c.line),
                  _PriceRow(
                    offer: offers[i],
                    minPrice: minPrice,
                    best: i == 0,
                    unit: product.unit,
                    productId: product.id,
                    productName: product.name,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Шапка таблицы. Колонки 5 / 3 / 3 / 2 — «НАЛИЧИЕ» и «Под заказ» по-русски
/// длиннее английского, на двух долях они переносятся.
class _PriceTableHeader extends StatelessWidget {
  const _PriceTableHeader();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = AppTypography.sectionLabel(color: c.faint).copyWith(fontSize: 10);

    return Container(
      color: _raised(c),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('ПОСТАВЩИК', style: s)),
          Expanded(
            flex: 3,
            child: Text('ЦЕНА', style: s, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 3,
            child: Text('НАЛИЧИЕ', style: s, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('СВЯЗЬ', style: s, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// Строка таблицы: поставщик, цена, наличие, связь.
class _PriceRow extends ConsumerWidget {
  const _PriceRow({
    required this.offer,
    required this.minPrice,
    required this.best,
    required this.unit,
    required this.productId,
    required this.productName,
  });

  final Offer offer;
  final double minPrice;
  final bool best;
  final String unit;
  final String productId;
  final String productName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final diff =
        minPrice == 0 ? 0 : ((offer.price - minPrice) / minPrice * 100).round();

    // Фиксируем обращение к поставщику и запускаем действие. Это целевое
    // действие приложения: по нему меряем, доходит ли человек от поиска
    // до звонка.
    void contact(Future<bool> Function() launch) {
      ref.read(eventsRepositoryProvider).logContact(productId, offer.supplierId);
      Analytics.log(Analytics.contactSupplier, {'product_id': productId});
      launch();
    }

    return Container(
      // Лучшее предложение выделено подложкой, а не рамкой: рамка внутри
      // таблицы сдвигает содержимое строки и ломает выравнивание колонок.
      color: best ? c.orangeSoft.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Имя ведёт в витрину поставщика: все его товары,
                    // контакты, годы на рынке, отзывы.
                    Flexible(
                      child: GestureDetector(
                        onTap: offer.supplierId == null
                            ? null
                            : () =>
                                context.push(Routes.supplier(offer.supplierId!)),
                        child: Text(
                          offer.supplierName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMd(color: c.ink)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    // Проверенная компания. Значок про документы, а не про
                    // оплату: на порядок в таблице он не влияет — выше стоит
                    // тот, у кого дешевле.
                    if (offer.supplierVerified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified, size: 13, color: c.green),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                if (best)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(AppRadii.xs),
                    ),
                    child: const Text(
                      'ЛУЧШАЯ ЦЕНА',
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.brandInk,
                      ),
                    ),
                  )
                else if (diff > 0)
                  Text('+$diff % к минимуму',
                      style: AppTypography.data(color: c.faint))
                else
                  Text(
                    offer.city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm(color: c.faint),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(Formatters.price(offer.price),
                    style:
                        AppTypography.priceMd(color: best ? c.accent : c.ink)),
                Text('за 1 $unit',
                    style: AppTypography.bodySm(color: c.gray)),
                // Своё изменение цены у этого поставщика — то, ради чего
                // люди подписываются на товар.
                if (offer.changePercent != null)
                  Text(
                    offer.changePercent! < 0
                        ? '▼ ${offer.changePercent!.abs()} %'
                        : '▲ ${offer.changePercent} %',
                    style: AppTypography.data(
                      color: offer.changePercent! < 0 ? c.green : c.red,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: offer.inStock ? c.green : c.faint,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  offer.inStock ? 'В наличии' : 'Под заказ',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm(
                      color: offer.inStock ? c.ink : c.faint),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (offer.phone != null)
                  _RowAction(
                    icon: Icons.call_outlined,
                    tooltip: 'Позвонить: ${offer.supplierName}',
                    onTap: () => contact(() => Launchers.call(offer.phone!)),
                  ),
                if (offer.whatsapp != null) ...[
                  if (offer.phone != null) const SizedBox(width: 6),
                  _RowAction(
                    icon: Icons.chat_outlined,
                    tooltip: 'Написать в WhatsApp',
                    onTap: () => contact(
                      () => Launchers.whatsapp(
                        offer.whatsapp!,
                        text: 'Здравствуйте! Интересует «$productName»',
                      ),
                    ),
                  ),
                ],
                // Сайт показываем только если звонить и писать некуда:
                // в строке помещаются две кнопки, третья ломает вёрстку.
                if (offer.phone == null &&
                    offer.whatsapp == null &&
                    offer.website != null)
                  _RowAction(
                    icon: Icons.link_rounded,
                    tooltip: 'Сайт поставщика',
                    onTap: () =>
                        contact(() => Launchers.website(offer.website!)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Кнопка связи в строке таблицы: 28×28, чтобы не раздувать высоту строки.
class _RowAction extends StatelessWidget {
  const _RowAction({
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _raised(c),
            borderRadius: BorderRadius.circular(AppRadii.xs),
          ),
          child: Icon(icon, size: 15, color: c.accent),
        ),
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

    final mn = product.minPrice;

    // Нижняя панель: слева минимальная цена, справа действие — как в макете.
    // Цену подняли сюда из шапки экрана: там она дублировала метку
    // «ЛУЧШАЯ ЦЕНА» в таблице, а здесь видна всегда, даже когда человек
    // дочитал до отзывов.
    return Container(
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              if (mn != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ЛУЧШЕЕ ПРЕДЛОЖЕНИЕ',
                        style: AppTypography.sectionLabel(color: c.faint)),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('от ',
                            style: AppTypography.bodySm(color: c.gray)),
                        Text(Formatters.price(mn),
                            style: AppTypography.priceLg(color: c.accent)),
                        Text(' / ${product.unit}',
                            style: AppTypography.bodySm(color: c.gray)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: inCollection ? c.green : c.accent,
                    foregroundColor:
                        inCollection ? Colors.white : AppColors.brandInk,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: Icon(inCollection ? Icons.check : Icons.add, size: 20),
                  label: Text(
                    needPicker
                        ? (inCollection
                            ? 'В подборках'
                            : 'Выбрать подборку')
                        : (inCollection ? 'В комплекте' : 'В комплект +'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () async {
                    // Подборки привязаны к аккаунту — сначала вход.
                    if (!ref.read(isSignedInProvider)) {
                      promptSignIn(context, 'Войдите, чтобы собрать комплект');
                      return;
                    }
                    if (needPicker) {
                      await showCollectionPicker(context, ref, product.id);
                      return;
                    }
                    try {
                      final name = await ref
                          .read(collectionsProvider.notifier)
                          .addToDefault(product.id);
                      if (context.mounted) {
                        _snack(context, 'Добавлено в «$name»');
                      }
                    } catch (_) {
                      if (context.mounted) {
                        _snack(context, 'Не сохранилось — проверьте связь');
                      }
                    }
                  },
                ),
              ),
            ],
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
      Analytics.log(Analytics.contactSupplier, {'product_id': product.id});
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

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
