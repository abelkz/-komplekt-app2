import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/product.dart';
import 'product_thumb.dart';

/// Спонсорская строка в списке категории/поиска.
///
/// Рекламирует конкретного поставщика, а не общую карточку: показывает
/// его имя и его цену, помечено «продвигается». Тап ведёт в карточку
/// товара, где покупатель видит всех и может позвонить.
class SponsoredRow extends StatelessWidget {
  const SponsoredRow({super.key, required this.entry});

  final SponsoredOffer entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = entry.product;
    final o = entry.offer;
    final supplier = o.supplierName.isEmpty ? 'поставщик' : o.supplierName;

    return Material(
      color: c.orangeSoft.withOpacity(0.35),
      child: InkWell(
        onTap: () => context.push(Routes.product(p.id)),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Жёлтая грань слева — маркер рекламного места
              Container(width: 3, color: c.orange),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
                child: ProductThumb(product: p, size: 54),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: c.orange,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('ПРОДВИГАЕТСЯ',
                                style: AppTypography.mono(
                                    size: 8.5,
                                    weight: FontWeight.w700,
                                    color: c.ink)),
                          ),
                          if (o.supplierVerified) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.verified, size: 13, color: c.orange),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        supplier,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.mono(size: 10.5, color: c.gray),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 16, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Formatters.price(o.price),
                        style: AppTypography.unbounded(size: 14, color: c.ink)),
                    const SizedBox(height: 4),
                    Text('₸/${p.unit}',
                        style: AppTypography.mono(size: 9.5, color: c.faint)),
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
