import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/onboarding/feature_tour.dart';
import '../../../core/providers/providers.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_input.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/domain/product.dart';
import '../../suppliers_map/domain/supplier.dart';
import 'supplier_cabinet_providers.dart';
import 'widgets/catalog_pick_sheet.dart';
import 'widgets/company_profile_sheet.dart';
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

// ───── Заявка: стать поставщиком ─────
class _BecomeSupplier extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BecomeSupplier> createState() => _BecomeSupplierState();
}

class _BecomeSupplierState extends ConsumerState<_BecomeSupplier> {
  final _company = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();
  String? _error;
  bool _prefilled = false;

  @override
  void dispose() {
    for (final c in [_company, _city, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_company.text.trim().isEmpty) {
      setState(() => _error = 'Укажите название компании');
      return;
    }
    final ok = await ref.read(cabinetControllerProvider.notifier).becomeSupplier(
          company: _company.text,
          city: _city.text,
          phone: _phone.text,
        );
    if (!ok && mounted) {
      final e = ref.read(cabinetControllerProvider).error;
      final t = e?.toString() ?? '';
      setState(() => _error =
          t.startsWith('Failure: ') ? t.substring(9) : 'Не удалось отправить заявку');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final loading = ref.watch(cabinetControllerProvider).isLoading;

    // подставляем то, что уже известно о пользователе
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final city = ref.watch(settingsProvider).city;
    if (!_prefilled && profile != null) {
      _prefilled = true;
      _city.text = profile.city.isNotEmpty ? profile.city : city;
      _phone.text = profile.phone ?? '';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration:
                  BoxDecoration(color: c.orangeSoft, shape: BoxShape.circle),
              child: Icon(Icons.storefront_outlined, size: 36, color: c.orange),
            ),
          ),
          const SizedBox(height: 18),
          Text('Размещайте товары и цены',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 8),
          Text(
            'Их увидят дизайнеры, комплектаторы и прорабы в приложении '
            'КОМПЛЕКТ. Заявку проверит администратор — обычно за один рабочий день.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.gray, height: 1.5),
          ),
          const SizedBox(height: 24),
          _label(c, 'Название компании'),
          TextField(
            controller: _company,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'ТОО «СтройДом»'),
          ),
          const SizedBox(height: 14),
          _label(c, 'Город'),
          TextField(
            controller: _city,
            decoration: const InputDecoration(hintText: 'Астана'),
          ),
          const SizedBox(height: 14),
          _label(c, 'Телефон для клиентов'),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: const [KzPhoneInputFormatter()],
            onTap: () {
              if (_phone.text.isEmpty) {
                _phone.text = KzPhoneInputFormatter.initial;
              }
            },
            decoration: const InputDecoration(hintText: '+7 700 000 0000'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: c.redSoft, borderRadius: BorderRadius.circular(AppRadii.sm)),
              child: Text(_error!,
                  style: TextStyle(color: c.red, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton(
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: loading ? null : _submit,
            child: loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.brandInk))
                : const Text('Отправить заявку'),
          ),
        ],
      ),
    );
  }

  Widget _label(AppColors c, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: c.gray)),
      );
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

class _CabinetBody extends ConsumerStatefulWidget {
  const _CabinetBody({required this.company});
  final Supplier company;

  @override
  ConsumerState<_CabinetBody> createState() => _CabinetBodyState();
}

class _CabinetBodyState extends ConsumerState<_CabinetBody> {
  Supplier get company => widget.company;

  @override
  void initState() {
    super.initState();
    // Знакомство с кабинетом при первом заходе
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTour());
  }

  Future<void> _maybeShowTour() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    FeatureTour.maybeShow(
      context,
      store: ref.read(localStoreProvider),
      id: 'supplier',
      steps: [
        TourStep(
          key: TourKeys.cabImport,
          title: 'Загрузите прайс',
          text: 'Excel-файл с наименованиями и ценами — весь ассортимент '
              'появится в каталоге за минуту.',
        ),
        TourStep(
          key: TourKeys.cabAdd,
          title: 'Добавьте товар вручную',
          text: 'Найдите товар в общем каталоге и поставьте свою цену — '
              'или создайте новую карточку с фото.',
        ),
        TourStep(
          key: TourKeys.cabLocation,
          title: 'Отметьте себя на карте',
          text: 'Укажите адрес и точку — покупатели рядом увидят вас '
              'на карте «Поставщики рядом».',
        ),
        TourStep(
          key: TourKeys.cabProfile,
          title: 'Заполните профиль компании',
          text: 'WhatsApp, сайт, год работы и описание — это видит '
              'покупатель на вашей витрине.',
        ),
        TourStep(
          key: TourKeys.cabPro,
          title: 'Тариф Pro',
          text: 'Продвижение товаров в топ, значок «проверенная компания» '
              'и статистика спроса.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
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
                        // Проверку документов ставит администратор
                        if (company.verified)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                                color: c.greenSoft,
                                borderRadius: BorderRadius.circular(999)),
                            child: Text('✓ проверенная компания',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: c.green)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Заметный баннер тарифа Pro — раньше был крохотной плашкой
          KeyedSubtree(
            key: TourKeys.cabPro,
            child: _SupplierProBanner(company: company),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: KeyedSubtree(
                  key: TourKeys.cabImport,
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
              ),
              const SizedBox(width: 9),
              Expanded(
                child: KeyedSubtree(
                  key: TourKeys.cabAdd,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить товар'),
                    onPressed: () => showCatalogPickSheet(context, company.id),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Место на карте: без координат компанию не видно на карте
          // «поставщики рядом»
          KeyedSubtree(
            key: TourKeys.cabLocation,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: c.ink,
                side: BorderSide(color: company.hasLocation ? c.line : c.orange),
                padding: const EdgeInsets.symmetric(vertical: 13),
                minimumSize: const Size.fromHeight(0),
              ),
              icon: Icon(
                  company.hasLocation
                      ? Icons.place
                      : Icons.add_location_alt_outlined,
                  size: 18,
                  color: company.hasLocation ? c.orange : c.orange),
              label: Text(company.hasLocation
                  ? 'Место на карте — изменить'
                  : 'Указать место на карте'),
              onPressed: () => context.push(Routes.supplierLocation),
            ),
          ),
          const SizedBox(height: 8),
          KeyedSubtree(
            key: TourKeys.cabProfile,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: c.ink,
                side: BorderSide(color: c.line),
                padding: const EdgeInsets.symmetric(vertical: 13),
                minimumSize: const Size.fromHeight(0),
              ),
              icon: Icon(Icons.storefront_outlined, size: 18, color: c.orange),
              label: const Text('Профиль компании — WhatsApp, год, описание'),
              onPressed: () => showCompanyProfileSheet(context, company),
            ),
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

/// Заметный баннер тарифа Pro для поставщика.
/// Без тарифа — яркий призыв с выгодами; с тарифом — спокойный статус.
class _SupplierProBanner extends StatelessWidget {
  const _SupplierProBanner({required this.company});
  final Supplier company;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pro = company.isPro;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: () => context.push(
          Routes.plans(forSupplier: true, supplierId: company.id)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // Без тарифа — заливка акцентом, чтобы бросалось в глаза
          color: pro ? c.orangeSoft : c.orange,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: c.orange, width: pro ? 1 : 0),
        ),
        child: Row(
          children: [
            Icon(pro ? Icons.workspace_premium : Icons.rocket_launch,
                color: pro ? c.orange : AppColors.brandInk, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pro ? 'Тариф Pro подключён' : 'Подключите тариф Pro',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: pro ? c.orange : AppColors.brandInk),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    pro
                        ? _untilText(company.planUntil)
                        : 'Продвижение товаров, значок «проверенный», '
                            'статистика спроса и прайс без ограничений.',
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: pro
                            ? c.gray
                            : AppColors.brandInk.withOpacity(0.85)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right,
                color: pro ? c.orange : AppColors.brandInk),
          ],
        ),
      ),
    );
  }

  static String _untilText(DateTime? until) {
    if (until == null) return 'Действует бессрочно.';
    final d = until.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return 'Действует до $dd.$mm.${d.year}. Нажмите, чтобы продлить.';
  }
}
