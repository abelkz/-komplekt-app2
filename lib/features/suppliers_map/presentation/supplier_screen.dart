import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/launchers.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/widgets/product_card.dart';
import '../domain/supplier.dart';
import 'suppliers_providers.dart';

/// Экран 9 — Витрина/профиль продавца: контакты + его товары.
class SupplierScreen extends ConsumerWidget {
  const SupplierScreen({super.key, required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplier = ref.watch(supplierProvider(supplierId));
    final products = ref.watch(supplierProductsProvider(supplierId));

    return Scaffold(
      appBar: AppBar(title: const Text('Витрина продавца')),
      body: AsyncValueView<Supplier>(
        value: supplier,
        onRetry: () => ref.invalidate(supplierProvider(supplierId)),
        data: (s) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(supplier: s)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('ТОВАРЫ ПРОДАВЦА',
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700,
                        color: context.colors.faint)),
              ),
            ),
            products.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5)),
                ),
              ),
              error: (_, __) => const SliverToBoxAdapter(
                child: EmptyState(title: 'Не удалось загрузить товары'),
              ),
              data: (list) => list.isEmpty
                  ? const SliverToBoxAdapter(
                      child: EmptyState(
                          title: 'У продавца пока нет товаров',
                          icon: Icons.inventory_2_outlined),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 11),
                        itemBuilder: (_, i) => ProductCard(product: list[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.supplier});
  final Supplier supplier;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: c.orangeSoft,
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.storefront_outlined, color: c.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(supplier.name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.star_rounded, size: 15, color: c.orange),
                        const SizedBox(width: 3),
                        Text(supplier.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 10),
                        Icon(Icons.location_on_outlined,
                            size: 14, color: c.gray),
                        const SizedBox(width: 3),
                        Text(supplier.city,
                            style: TextStyle(fontSize: 12, color: c.gray)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (supplier.address != null) ...[
            const SizedBox(height: 10),
            Text(supplier.address!,
                style: TextStyle(fontSize: 13, color: c.gray)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (supplier.phone != null)
                Expanded(
                  child: _ContactButton(
                    icon: Icons.call_outlined,
                    label: 'Позвонить',
                    onTap: () => Launchers.call(supplier.phone!),
                  ),
                ),
              if (supplier.whatsapp != null) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: _ContactButton(
                    icon: Icons.chat_outlined,
                    label: 'WhatsApp',
                    onTap: () => Launchers.whatsapp(supplier.whatsapp!),
                  ),
                ),
              ],
              if (supplier.website != null) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: _ContactButton(
                    icon: Icons.link_rounded,
                    label: 'Сайт',
                    onTap: () => Launchers.website(supplier.website!),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton(
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
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
            color: c.field, borderRadius: BorderRadius.circular(AppRadii.sm)),
        child: Column(
          children: [
            Icon(icon, size: 18, color: c.ink),
            const SizedBox(height: 4),
            Text(label,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
