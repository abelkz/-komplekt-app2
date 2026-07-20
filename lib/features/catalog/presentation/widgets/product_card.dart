import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/product.dart';
import 'product_thumb.dart';

/// Строка ленты-спецификации: № · фото · название · мин. цена · дельта.
/// Строки идут вплотную и разделяются волосяной линейкой — вместе они
/// читаются как таблица документа, а не как набор карточек.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.index,
    this.compact = false,
  });

  final Product product;

  /// Порядковый номер в ленте: рисуется как 01, 02, 03…
  /// Если не передан, колонка с номером не показывается.
  final int? index;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mn = product.minPrice;
    final saving = product.savingPercent;
    final thumb = compact ? 46.0 : 60.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(Routes.product(product.id)),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (index != null)
                Container(
                  width: 40,
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: c.line)),
                  ),
                  padding: const EdgeInsets.only(top: 12),
                  alignment: Alignment.topCenter,
                  child: Text(
                    (index! + 1).toString().padLeft(2, '0'),
                    style: AppTypography.mono(size: 10, color: c.faint),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: ProductThumb(product: product, size: thumb),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 10, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _meta(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.mono(size: 10.5, color: c.gray),
                      ),
                    ],
                  ),
                ),
              ),
              if (mn != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        Formatters.price(mn),
                        style: AppTypography.unbounded(size: 14, color: c.ink),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        saving > 0 ? '▼ $saving%' : '—',
                        style: AppTypography.mono(
                          size: 10,
                          weight: FontWeight.w700,
                          color: saving > 0 ? c.green : c.faint,
                        ),
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
    final parts = <String>[
      if (product.offersCount > 0)
        '${product.offersCount} ${_plural(product.offersCount)}',
      if (product.unit.isNotEmpty) '₸/${product.unit}',
    ];
    if (parts.isEmpty && product.sku.isNotEmpty) return 'арт. ${product.sku}';
    return parts.join(' · ');
  }

  static String _plural(int n) {
    final m = n % 10, h = n % 100;
    if (m == 1 && h != 11) return 'поставщик';
    if (m >= 2 && m <= 4 && (h < 10 || h >= 20)) return 'поставщика';
    return 'поставщиков';
  }
}

/// Волосяной разделитель между строками ленты.
class SpecDivider extends StatelessWidget {
  const SpecDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: context.colors.line);
}

/// Жирная линейка — открывает и закрывает ленту-спецификацию.
class SpecEdge extends StatelessWidget {
  const SpecEdge({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1.5, thickness: 1.5, color: context.colors.ink);
}
