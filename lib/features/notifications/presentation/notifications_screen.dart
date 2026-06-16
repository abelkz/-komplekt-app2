import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../domain/price_drop.dart';
import 'notifications_providers.dart';

/// Экран истории уведомлений о снижении цены.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Открыли экран — помечаем всё прочитанным и сбрасываем бейдж.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(notificationsRepositoryProvider).markAllRead();
      ref.invalidate(unreadCountProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Уведомления о ценах')),
      body: AsyncValueView<List<PriceDrop>>(
        value: notifications,
        onRetry: () => ref.invalidate(notificationsProvider),
        isEmpty: (d) => d.isEmpty,
        empty: const EmptyState(
          title: 'Пока нет уведомлений',
          subtitle:
              'Добавляйте товары в избранное — сообщим, когда цена снизится.',
          icon: Icons.notifications_none_rounded,
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(notificationsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 11),
            itemBuilder: (_, i) => _NotificationCard(drop: list[i]),
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.drop});
  final PriceDrop drop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: drop.productId == null
            ? null
            : () => context.push(Routes.product(drop.productId!)),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.greenSoft,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(Icons.trending_down_rounded, color: c.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(drop.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          Formatters.price(drop.oldPrice),
                          style: TextStyle(
                            fontSize: 12,
                            color: c.faint,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.arrow_right_alt_rounded,
                            size: 16, color: c.gray),
                        const SizedBox(width: 6),
                        Text(
                          Formatters.price(drop.newPrice),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: c.ink),
                        ),
                        if (drop.discountPercent > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                                color: c.greenSoft,
                                borderRadius: BorderRadius.circular(999)),
                            child: Text('−${drop.discountPercent}%',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: c.green)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        if (drop.supplierName.isNotEmpty) drop.supplierName,
                        Formatters.relativeDate(drop.createdAt),
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style: TextStyle(fontSize: 11, color: c.faint),
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
