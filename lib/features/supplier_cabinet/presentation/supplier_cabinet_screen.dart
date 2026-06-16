import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/domain/product.dart';
import '../../suppliers_map/domain/supplier.dart';
import 'supplier_cabinet_providers.dart';
import 'widgets/add_product_sheet.dart';
import 'widgets/import_price_sheet.dart';
import 'widgets/product_edit_row.dart';

/// Экран 10 — Кабинет поставщика. Поведение зависит от роли/статуса:
/// не поставщик → CTA; pending → ожидание; rejected → отказ; approved → кабинет.
class SupplierCabinetScreen extends ConsumerWidget {
  const SupplierCabinetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Кабинет поставщика')),
      body: AsyncValueView<AppUser?>(
        value: profile,
        onRetry: () => ref.invalidate(myProfileProvider),
        data: (user) {
          if (user == null) {
            return const EmptyState(title: 'Войдите в аккаунт');
          }
          if (!user.isSupplier) return _BecomeSupplier();
          if (user.isPending) return const _StatusCard(pending: true);
          if (user.isRejected) return const _StatusCard(pending: false);
          return const _Cabinet();
        },
      ),
    );
  }
}

// ───── CTA: стать поставщиком ─────
class _BecomeSupplier extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final loading = ref.watch(cabinetControllerProvider).isLoading;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration:
                  BoxDecoration(color: c.orangeSoft, shape: BoxShape.circle),
              child: Icon(Icons.storefront_outlined, size: 44, color: c.orange),
            ),
            const SizedBox(height: 22),
            Text('Размещайте товары и цены',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 10),
            Text(
              'Их увидят дизайнеры, комплектаторы и прорабы в приложении '
              'КОМПЛЕКТ. После заявки компанию проверит администратор.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.gray, height: 1.5),
            ),
            const SizedBox(height: 26),
            FilledButton(
              onPressed: loading
                  ? null
                  : () =>
                      ref.read(cabinetControllerProvider.notifier).becomeSupplier(),
              child: loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Стать поставщиком'),
            ),
          ],
        ),
      ),
    );
  }
}

// ───── Ожидание/отказ ─────
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.pending});
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(pending ? Icons.hourglass_top_rounded : Icons.cancel_outlined,
                size: 56, color: pending ? c.orange : c.red),
            const SizedBox(height: 16),
            Text(pending ? 'Заявка на проверке' : 'Заявка отклонена',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 8),
            Text(
              pending
                  ? 'Мы проверяем компанию. После одобрения здесь откроется '
                      'управление товарами — обычно это занимает до 1 рабочего дня.'
                  : 'Если считаете это ошибкой — свяжитесь с поддержкой КОМПЛЕКТ.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.gray, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ───── Кабинет одобренного поставщика ─────
class _Cabinet extends ConsumerWidget {
  const _Cabinet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(myCompanyProvider);
    return AsyncValueView<Supplier>(
      value: company,
      onRetry: () => ref.invalidate(myCompanyProvider),
      data: (comp) => _CabinetBody(company: comp),
    );
  }
}

class _CabinetBody extends ConsumerWidget {
  const _CabinetBody({required this.company});
  final Supplier company;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final products = ref.watch(myProductsProvider);
    final stats = ref.watch(myStatsProvider).valueOrNull ?? const {};

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myProductsProvider);
        ref.invalidate(myStatsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(company.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                          color: c.greenSoft,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text('✓ поставщик одобрен',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: c.green)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.line),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Загрузить прайс'),
                  onPressed: () => showImportPriceSheet(context, company.id),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Добавить товар'),
                  onPressed: () => showAddProductSheet(context, company.id),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          products.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            ),
            error: (e, _) => EmptyState(
                title: 'Ошибка',
                subtitle: e.toString().replaceFirst('Failure: ', '')),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: EmptyState(
                      title: 'Товаров пока нет',
                      subtitle: 'Добавьте первый товар или загрузите прайс.',
                      icon: Icons.inventory_2_outlined,
                    ),
                  )
                : Column(
                    children: [
                      for (final p in list)
                        ProductEditRow(
                          product: p,
                          supplierId: company.id,
                          stat: stats[p.id],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
