import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../data/price_history_repository.dart';

/// История цен — возможность тарифа КОМПЛЕКТ Про.
///
/// Без тарифа показываем, что именно человек получит, и ведём на экран
/// тарифа. С тарифом — минимальная цена по дням и последние изменения.
class PriceHistorySection extends ConsumerWidget {
  const PriceHistorySection({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final isPro = ref.watch(myProfileProvider).valueOrNull?.isPro ?? false;

    if (!isPro) return _Locked(productId: productId);

    final history = ref.watch(priceHistoryProvider(productId));
    return history.when(
      loading: () => const SizedBox(height: 92),
      error: (_, __) => const SizedBox.shrink(),
      data: (points) {
        if (points.length < 2) {
          return _Frame(
            child: Text(
              'Цена ещё не менялась — как только поставщик её обновит, '
              'изменение появится здесь.',
              style: TextStyle(fontSize: 13, color: c.gray, height: 1.35),
            ),
          );
        }

        // По дню берём минимум — покупателя интересует лучшая цена дня
        final byDay = <DateTime, double>{};
        for (final p in points) {
          final d = DateTime(p.at.year, p.at.month, p.at.day);
          byDay[d] = byDay[d] == null ? p.price : (byDay[d]! < p.price ? byDay[d]! : p.price);
        }
        final days = byDay.keys.toList()..sort();
        final series = [for (final d in days) byDay[d]!];

        final first = series.first;
        final last = series.last;
        final diff = last - first;
        final percent = first == 0 ? 0 : (diff / first * 100).round();

        return _Frame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BarChart(
                values: series.length > 16
                    ? series.sublist(series.length - 16)
                    : series,
              ),
              const SizedBox(height: 12),
              Text(
                diff == 0
                    ? 'Цена держится на ${Formatters.price(last)}'
                    : diff < 0
                        ? 'Дешевле на ${Formatters.price(-diff)} (${-percent}%) '
                            'с ${_d(days.first)}'
                        : 'Дороже на ${Formatters.price(diff)} ($percent%) '
                            'с ${_d(days.first)}',
                style: TextStyle(fontSize: 13, color: c.ink, height: 1.35),
              ),
              const SizedBox(height: 10),
              for (final p in points.reversed.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54,
                        child: Text(_d(p.at),
                            style: AppTypography.mono(size: 11, color: c.gray)),
                      ),
                      Expanded(
                        child: Text(
                          p.supplier.isEmpty ? 'поставщик' : p.supplier,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.gray),
                        ),
                      ),
                      Text(Formatters.price(p.price),
                          style: AppTypography.mono(size: 12, color: c.ink)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
}

/// Общая рамка с заголовком раздела.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ИСТОРИЯ ЦЕН', style: AppTypography.sectionLabel(color: c.gray)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.card,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked({required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Frame(
      child: InkWell(
        onTap: () => context.push(Routes.plans()),
        child: Row(
          children: [
            Icon(Icons.show_chart, size: 20, color: c.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Как менялась цена у каждого поставщика — в тарифе '
                'КОМПЛЕКТ Про. Видно, когда выгоднее закупаться.',
                style: TextStyle(fontSize: 13, color: c.gray, height: 1.35),
              ),
            ),
            Icon(Icons.chevron_right, color: c.orange),
          ],
        ),
      ),
    );
  }
}

/// Столбчатая диаграмма минимальных цен по дням — последний столбик золотой
/// (текущая цена), как в макете.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.values});
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (values.isEmpty) return const SizedBox(height: 120);

    var mn = values.first, mx = values.first;
    for (final v in values) {
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    final span = (mx - mn).abs() < 0.01 ? 1.0 : mx - mn;

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: 14 + (values[i] - mn) / span * 100,
                    decoration: BoxDecoration(
                      color: i == values.length - 1 ? c.orange : c.line,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
