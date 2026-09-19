import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/pricing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/launchers.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../auth/domain/app_user.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../catalog/presentation/widgets/quick_filters.dart';
import '../data/admin_repository.dart';
import 'admin_providers.dart';
import 'widgets/supplier_actions_sheet.dart';

/// Экран администратора: заявки поставщиков и заявки на платный тариф.
/// Открывается только с учётной записи с ролью admin.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isAdminProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Панель')),
        body: const Center(child: Text('Раздел доступен только администратору')),
      );
    }

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Панель'),
          bottom: const TabBar(isScrollable: true, tabs: [
            // Сводка первой: с неё смотрят, что вообще происходит,
            // а разбор заявок — уже следствие.
            Tab(text: 'Сводка'),
            Tab(text: 'Поставщики'),
            Tab(text: 'Тарифы'),
            Tab(text: 'Буст'),
            Tab(text: 'Жалобы'),
            // Марки последними: это наведение порядка, а не разбор дел —
            // сюда заходят по необходимости, а не каждый день.
            Tab(text: 'Марки'),
          ]),
        ),
        body: const TabBarView(children: [
          _StatsTab(),
          _SuppliersTab(),
          _PlansTab(),
          _BoostTab(),
          _ReportsTab(),
          _BrandsTab(),
        ]),
      ),
    );
  }
}

// ──────────────────────────── Сводка ────────────────────────────

/// Что происходит в приложении: регистрации, спрос, отдача поставщикам.
///
/// Считает база (миграция 0030) — здесь только показ. Важное про числа:
/// события `app_events` пишутся начиная с версии 1.0.1, поэтому поиск и
/// открытия категорий за длинный период выглядят заниженными относительно
/// обращений, которые копятся с самого начала. Это не ошибка расчёта,
/// и об этом честнее сказать прямо на экране, чем дать себя обмануть.
class _StatsTab extends ConsumerWidget {
  const _StatsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(statsPeriodProvider);
    final overview = ref.watch(adminOverviewProvider);

    void reload() {
      ref.invalidate(adminOverviewProvider);
      ref.invalidate(adminTopSearchesProvider);
      ref.invalidate(adminTopCategoriesProvider);
      ref.invalidate(adminSupplierStatsProvider);
    }

    return RefreshIndicator(
      onRefresh: () async => reload(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _PeriodPicker(days: days),
          const SizedBox(height: 14),
          AsyncValueView<AdminOverview>(
            value: overview,
            onRetry: reload,
            data: (o) => _OverviewGrid(o: o, days: days),
          ),
          const SizedBox(height: 22),
          _CountedList(
            title: 'ЧТО ИСКАЛИ',
            note: 'По этим запросам видно, каких материалов не хватает '
                'в каталоге.',
            value: ref.watch(adminTopSearchesProvider),
            onRetry: reload,
            empty: 'За период никто не искал',
          ),
          const SizedBox(height: 22),
          _CountedList(
            title: 'КАТЕГОРИИ',
            note: 'Какие разделы открывают, а какие лежат мёртвым грузом.',
            value: ref.watch(adminTopCategoriesProvider),
            onRetry: reload,
            empty: 'За период категории не открывали',
          ),
          const SizedBox(height: 22),
          _SupplierStatsList(
            value: ref.watch(adminSupplierStatsProvider),
            onRetry: reload,
          ),
        ],
      ),
    );
  }
}

class _PeriodPicker extends ConsumerWidget {
  const _PeriodPicker({required this.days});
  final int days;

  static const _options = {7: 'Неделя', 30: 'Месяц', 90: '3 месяца', 365: 'Год'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Row(
      children: [
        for (final e in _options.entries) ...[
          InkWell(
            onTap: () => ref.read(statsPeriodProvider.notifier).set(e.key),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: days == e.key ? c.accent : c.field,
                border: Border.all(color: days == e.key ? c.accent : c.line),
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Text(
                e.value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: days == e.key ? AppColors.brandInk : c.gray,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.o, required this.days});
  final AdminOverview o;
  final int days;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: _Stat(
              label: 'Всего людей',
              value: '${o.usersTotal}',
              hint: '+${o.usersNew} за период',
              accent: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Stat(
              label: 'Поставщиков',
              value: '${o.suppliersTotal}',
              hint: o.suppliersPending > 0
                  ? '${o.suppliersPending} ждут проверки'
                  : 'все проверены',
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _Stat(
              label: 'Обращения',
              value: '${o.contacts}',
              hint: 'звонки и WhatsApp',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Stat(
              label: 'Каталог',
              value: '${o.productsTotal}',
              hint: '${o.offersTotal} цен от поставщиков',
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _Stat(
              label: 'Открыли товар',
              value: '${o.productViews}',
              hint: '${o.categoryOpens} открытий категорий',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Stat(
              label: 'Поисков',
              value: '${o.searches}',
              hint: '${o.favoritesTotal} в избранном',
            ),
          ),
        ]),
        if (o.paidTotal > 0) ...[
          const SizedBox(height: 10),
          _Stat(
            label: 'Оплачено за период',
            value: Formatters.price(o.paidTotal),
            hint: 'только успешные платежи',
            accent: true,
          ),
        ],
        const SizedBox(height: 10),
        // Без этой оговорки числа читаются неверно: обращения копятся
        // с самого начала, а поиск и категории — только с версии 1.0.1.
        Text(
          'Поиск, открытия товаров и категорий считаются с версии 1.0.1. '
          'Обращения к поставщикам — за всё время работы.',
          style: TextStyle(fontSize: 11, color: c.faint, height: 1.35),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.hint,
    this.accent = false,
  });

  final String label;
  final String value;
  final String? hint;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: accent ? c.accent : c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: c.faint)),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: accent ? c.accent : c.ink)),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!,
                maxLines: 2,
                style: TextStyle(fontSize: 11, color: c.gray)),
          ],
        ],
      ),
    );
  }
}

/// Список «строка — число» с полосой относительной величины.
class _CountedList extends StatelessWidget {
  const _CountedList({
    required this.title,
    required this.value,
    required this.onRetry,
    required this.empty,
    this.note,
  });

  final String title;
  final AsyncValue<List<CountedRow>> value;
  final VoidCallback onRetry;
  final String empty;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: c.faint)),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note!, style: TextStyle(fontSize: 11, color: c.gray)),
        ],
        const SizedBox(height: 10),
        AsyncValueView<List<CountedRow>>(
          value: value,
          onRetry: onRetry,
          isEmpty: (d) => d.isEmpty,
          empty: _Empty(empty),
          data: (rows) {
            final max = rows.first.n.clamp(1, 1 << 30);
            return Column(
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13, color: c.ink)),
                              const SizedBox(height: 4),
                              // Полоса вместо графика: сравнивать строки между
                              // собой глазами так быстрее, чем читать числа.
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: r.n / max,
                                  minHeight: 4,
                                  backgroundColor: c.field,
                                  valueColor:
                                      AlwaysStoppedAnimation(c.accent),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('${r.n}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: c.ink)),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Поставщики по отдаче: у кого звонят, а кто завёл компанию и забыл.
class _SupplierStatsList extends StatelessWidget {
  const _SupplierStatsList({required this.value, required this.onRetry});

  final AsyncValue<List<SupplierRow>> value;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ПОСТАВЩИКИ',
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: c.faint)),
        const SizedBox(height: 4),
        Text('Сверху те, кому звонят. Просмотр можно накрутить, звонок — нет.',
            style: TextStyle(fontSize: 11, color: c.gray)),
        const SizedBox(height: 10),
        AsyncValueView<List<SupplierRow>>(
          value: value,
          onRetry: onRetry,
          isEmpty: (d) => d.isEmpty,
          empty: const _Empty('Поставщиков пока нет'),
          data: (rows) => Column(
            children: [
              for (final s in rows)
                Builder(
                  builder: (context) => InkWell(
                    onTap: () => showSupplierActions(context, s),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: _SupplierStatCard(s: s),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupplierStatCard extends StatelessWidget {
  const _SupplierStatCard({required this.s});
  final SupplierRow s;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        // Заблокированную обводим красным: в списке из двух десятков строк
        // подпись мелким шрифтом можно и не заметить.
        border: Border.all(color: s.isBlocked ? c.red : c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (s.isBlocked)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.block, size: 15, color: c.red),
                ),
              Expanded(
                child: Text(s.name.isEmpty ? 'без названия' : s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (s.verified)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.verified, size: 15, color: c.accent),
                ),
              if (s.isPro)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('PRO',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: c.accent)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (s.city.isNotEmpty) s.city,
              '${s.products} товаров',
              '${s.offers} цен',
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: c.faint),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _mini(c, Icons.visibility_outlined, '${s.views}', 'просмотров'),
              const SizedBox(width: 16),
              _mini(c, Icons.call_outlined, '${s.contacts}', 'обращений'),
            ],
          ),
          // Дата последней правки прайса — главный признак живой компании.
          if (s.lastPriceAt != null) ...[
            const SizedBox(height: 6),
            Text('Прайс обновлён ${Formatters.relativeDate(s.lastPriceAt)}',
                style: TextStyle(fontSize: 11, color: c.gray)),
          ] else ...[
            const SizedBox(height: 6),
            Text('Цены ни разу не обновлялись',
                style: TextStyle(fontSize: 11, color: c.red)),
          ],
          if (s.isBlocked) ...[
            const SizedBox(height: 6),
            Text(
              [
                s.blockedForever
                    ? 'Заблокирована бессрочно'
                    : 'Заблокирована до ${_date(s.blockedUntil!)}',
                if (s.blockReason != null && s.blockReason!.isNotEmpty)
                  s.blockReason!,
              ].join(' · '),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: c.red),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mini(AppColors c, IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c.faint),
        const SizedBox(width: 5),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: c.faint)),
      ],
    );
  }
}

// ─────────────────────────── Поставщики ───────────────────────────

class _SuppliersTab extends ConsumerWidget {
  const _SuppliersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(supplierApplicationsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(supplierApplicationsProvider),
      child: AsyncValueView<List<AppUser>>(
        value: list,
        onRetry: () => ref.invalidate(supplierApplicationsProvider),
        isEmpty: (d) => d.isEmpty,
        empty: const _Empty('Заявок от поставщиков пока нет'),
        data: (all) {
          // Ожидающие проверки — наверх: с ними и нужно что-то делать
          final sorted = [...all]..sort((a, b) {
              if (a.isPending == b.isPending) return 0;
              return a.isPending ? -1 : 1;
            });
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: sorted.length,
            itemBuilder: (_, i) => _SupplierCard(user: sorted[i]),
          );
        },
      ),
    );
  }
}

class _SupplierCard extends ConsumerStatefulWidget {
  const _SupplierCard({required this.user});
  final AppUser user;

  @override
  ConsumerState<_SupplierCard> createState() => _SupplierCardState();
}

class _SupplierCardState extends ConsumerState<_SupplierCard> {
  bool _busy = false;

  Future<void> _set(String status) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(adminRepositoryProvider)
          .setSupplierStatus(widget.user.id, status);
      ref.invalidate(supplierApplicationsProvider);
      messenger.showSnackBar(SnackBar(
          content: Text(status == 'approved'
              ? 'Поставщик одобрен'
              : 'Заявка отклонена')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final c = context.colors;

    return _Card(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                u.company.isNotEmpty ? u.company : 'Без названия',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            _Tag(
              text: u.isPending
                  ? 'на проверке'
                  : u.isRejected
                      ? 'отклонён'
                      : 'работает',
              color: u.isPending
                  ? c.orange
                  : u.isRejected
                      ? c.red
                      : c.green,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          [
            if (u.fullName.isNotEmpty) u.fullName,
            if (u.city.isNotEmpty) u.city,
          ].join(' · '),
          style: TextStyle(fontSize: 13, color: c.gray),
        ),
        if ((u.phone ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          _ContactRow(phone: u.phone!),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            if (!u.isApproved)
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _set('approved'),
                  child: const Text('Одобрить'),
                ),
              ),
            if (!u.isApproved && !u.isRejected) const SizedBox(width: 8),
            if (!u.isRejected)
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: c.red),
                  onPressed: _busy ? null : () => _set('rejected'),
                  child: const Text('Отклонить'),
                ),
              ),
            if (u.isRejected)
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _set('pending'),
                  child: const Text('Вернуть на проверку'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ──────────────────────────── Тарифы ────────────────────────────

class _PlansTab extends ConsumerWidget {
  const _PlansTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(subscriptionRequestsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(subscriptionRequestsProvider),
      child: AsyncValueView<List<SubRequest>>(
        value: list,
        onRetry: () => ref.invalidate(subscriptionRequestsProvider),
        isEmpty: (d) => d.isEmpty,
        empty: const _Empty('Заявок на тариф пока нет'),
        data: (all) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: all.length,
          itemBuilder: (_, i) => _RequestCard(request: all[i]),
        ),
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({required this.request});
  final SubRequest request;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  int _months = 1;
  bool _busy = false;

  Future<void> _activate() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ref
          .read(adminRepositoryProvider)
          .activate(widget.request.id, _months);
      ref.invalidate(subscriptionRequestsProvider);
      messenger.showSnackBar(SnackBar(content: Text(res)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _status(String status) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(adminRepositoryProvider)
          .setRequestStatus(widget.request.id, status);
      ref.invalidate(subscriptionRequestsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final c = context.colors;
    final who = r.who;
    final title = who == null
        ? 'Пользователь'
        : (who.company.isNotEmpty ? who.company : who.fullName);
    final phone = who?.phone ?? '';

    return _Card(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title.isEmpty ? 'Без названия' : title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            _Tag(
              text: r.forSupplier ? 'Тариф Про' : 'КОМПЛЕКТ Про',
              color: c.orange,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${_date(r.createdAt)}'
          '${r.status == 'new' ? '' : ' · ${_statusLabel(r.status)}'}',
          style: TextStyle(fontSize: 13, color: c.gray),
        ),
        if (r.planActive) ...[
          const SizedBox(height: 6),
          Text(
            r.planUntil == null
                ? 'Тариф включён бессрочно'
                : 'Тариф включён до ${_date(r.planUntil!)}',
            style: TextStyle(
                fontSize: 13, color: c.green, fontWeight: FontWeight.w600),
          ),
        ],
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ContactRow(phone: phone),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Text('Срок', style: TextStyle(fontSize: 13, color: c.gray)),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _months,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 мес')),
                DropdownMenuItem(value: 3, child: Text('3 мес')),
                DropdownMenuItem(value: 6, child: Text('6 мес')),
                DropdownMenuItem(value: 12, child: Text('12 мес')),
              ],
              onChanged: _busy ? null : (v) => setState(() => _months = v ?? 1),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _activate,
              child: Text(r.planActive ? 'Продлить' : 'Включить'),
            ),
          ],
        ),
        if (r.isNew)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: c.gray),
              onPressed: _busy ? null : () => _status('declined'),
              child: const Text('Отказ'),
            ),
          ),
      ],
    );
  }
}

// ──────────────────────────── Буст ────────────────────────────

class _BoostTab extends ConsumerWidget {
  const _BoostTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(boostOrdersProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(boostOrdersProvider),
      child: AsyncValueView<List<SubRequest>>(
        value: list,
        onRetry: () => ref.invalidate(boostOrdersProvider),
        isEmpty: (d) => d.isEmpty,
        empty: const _Empty('Заявок на Буст пока нет'),
        data: (all) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: all.length,
          itemBuilder: (_, i) => _BoostCard(order: all[i]),
        ),
      ),
    );
  }
}

class _BoostCard extends ConsumerStatefulWidget {
  const _BoostCard({required this.order});
  final SubRequest order;

  @override
  ConsumerState<_BoostCard> createState() => _BoostCardState();
}

class _BoostCardState extends ConsumerState<_BoostCard> {
  bool _busy = false;

  Future<void> _grant() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await ref.read(adminRepositoryProvider).grantBoost(widget.order.id);
      ref.invalidate(boostOrdersProvider);
      messenger.showSnackBar(
          SnackBar(content: Text('Начислено подъёмов: $n')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminRepositoryProvider).setBoostStatus(widget.order.id, 'declined');
      ref.invalidate(boostOrdersProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final c = context.colors;
    final who = o.who;
    final title = who == null
        ? 'Поставщик'
        : (who.company.isNotEmpty ? who.company : who.fullName);
    final phone = who?.phone ?? '';
    final done = !o.isNew;

    return _Card(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title.isEmpty ? 'Поставщик' : title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            _Tag(
              text: o.status == 'paid'
                  ? 'выдан'
                  : o.status == 'declined'
                      ? 'отказ'
                      : 'новая',
              color: o.status == 'paid'
                  ? c.green
                  : o.status == 'declined'
                      ? c.red
                      : c.orange,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${o.boostQty} × подъём на ${o.boostDays} '
          '${o.boostDays == 1 ? 'день' : 'дней'} · ${_boostSum(o)} · '
          '${_date(o.createdAt)}',
          style: TextStyle(fontSize: 13, color: c.gray),
        ),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ContactRow(phone: phone),
        ],
        const SizedBox(height: 12),
        if (!done)
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _grant,
                  child: const Text('Оплачено — начислить'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: c.red),
                onPressed: _busy ? null : _decline,
                child: const Text('Отказ'),
              ),
            ],
          ),
      ],
    );
  }
}

// ──────────────────────────── Общее ────────────────────────────

String _msg(Object e) {
  final t = e.toString();
  return t.startsWith('Failure: ') ? t.substring(9) : 'Не получилось';
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Сумма заявки на Буст по единому прайсу (Pricing).
String _boostSum(SubRequest o) {
  final total = (Pricing.boost[o.boostDays] ?? 0) * o.boostQty;
  final s = total.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b ₸';
}

String _statusLabel(String s) => switch (s) {
      'contacted' => 'связались',
      'paid' => 'оплачено',
      'declined' => 'отказ',
      _ => s,
    };

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w700)),
      );
}

/// Телефон заявителя с быстрым звонком и перепиской.
class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.phone});
  final String phone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Text(phone, style: TextStyle(fontSize: 13, color: c.ink)),
        const SizedBox(width: 10),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.call_outlined, size: 18),
          onPressed: () => Launchers.call(phone),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chat_outlined, size: 18),
          onPressed: () => Launchers.whatsapp(phone),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.gray)),
        ),
      );
}

/// Разбор жалоб на отзывы. Появился вместе с миграцией 0025 — до неё жалобы
/// не сохранялись вовсе.
class _ReportsTab extends ConsumerWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(contentReportsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(contentReportsProvider),
      child: AsyncValueView<List<ContentReport>>(
        value: list,
        onRetry: () => ref.invalidate(contentReportsProvider),
        isEmpty: (d) => d.isEmpty,
        empty: const _Empty('Жалоб пока нет'),
        data: (all) {
          // Неразобранные наверх — с ними и нужно что-то делать.
          final sorted = [...all]..sort((a, b) {
              if (a.isNew == b.isNew) return 0;
              return a.isNew ? -1 : 1;
            });
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: sorted.length,
            itemBuilder: (_, i) => _ReportCard(report: sorted[i]),
          );
        },
      ),
    );
  }
}

class _ReportCard extends ConsumerStatefulWidget {
  const _ReportCard({required this.report});
  final ContentReport report;

  @override
  ConsumerState<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<_ReportCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      ref.invalidate(contentReportsProvider);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      final t = e.toString();
      messenger.showSnackBar(SnackBar(
          content: Text(t.startsWith('Failure: ') ? t.substring(9) : 'Ошибка')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Удаление необратимо, поэтому спрашиваем подтверждение.
  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Удалить отзыв?'),
        content: const Text(
            'Отзыв исчезнет у всех, и все жалобы на него закроются. '
            'Отменить будет нельзя.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(adminRepositoryProvider).deleteReview(widget.report),
      'Отзыв удалён',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.report;
    final text = r.reviewText;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: r.isNew ? c.orange : c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                r.onSupplier ? 'Отзыв о поставщике' : 'Отзыв о товаре',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(Formatters.relativeDate(r.createdAt),
                  style: TextStyle(fontSize: 11, color: c.faint)),
            ],
          ),
          const SizedBox(height: 8),

          // Текста может не быть: отзыв уже удалён или недоступен.
          Text(
            (text == null)
                ? 'Отзыв не найден — возможно, уже удалён'
                : (text.isEmpty ? 'Отзыв без текста, только оценка' : text),
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: text == null ? c.faint : c.ink,
              fontStyle: text == null ? FontStyle.italic : FontStyle.normal,
            ),
          ),

          const SizedBox(height: 8),
          Text(
            r.reporterName?.isNotEmpty == true
                ? 'Пожаловался: ${r.reporterName}'
                : 'Пожаловался гость',
            style: TextStyle(fontSize: 11, color: c.gray),
          ),

          if (!r.isNew) ...[
            const SizedBox(height: 6),
            Text('Статус: ${_statusLabel(r.status)}',
                style: TextStyle(fontSize: 11, color: c.faint)),
          ],

          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy || text == null ? null : _confirmDelete,
                style: FilledButton.styleFrom(backgroundColor: c.red),
                child: const Text('Удалить отзыв'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                          () => ref
                              .read(adminRepositoryProvider)
                              .setReportStatus(r.id, 'rejected'),
                          'Жалоба отклонена',
                        ),
                child: const Text('Не нарушает'),
              ),
              if (r.isNew)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => ref
                                .read(adminRepositoryProvider)
                                .setReportStatus(r.id, 'reviewed'),
                            'Помечено как разобранное',
                          ),
                  child: const Text('Разобрано'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _statusLabel(String s) => switch (s) {
        'removed' => 'отзыв удалён',
        'rejected' => 'нарушений нет',
        'reviewed' => 'разобрано',
        _ => s,
      };
}

// ──────────────────────────── Марки ────────────────────────────

/// Наведение порядка в марках (миграция 0035).
///
/// Марку заводит любой поставщик, вписав её в форму товара, а нормализация
/// в `set_product_brand` ловит только регистр и пробелы. Кириллическую
/// «Керама Марацци» от латинской «Kerama Marazzi» она не отличит, а
/// латинскую C от кириллической С в «Cersanit» не отличит и человек —
/// поэтому склейка дубликатов нужна вручную.
class _BrandsTab extends ConsumerWidget {
  const _BrandsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(adminBrandsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(adminBrandsProvider),
      child: AsyncValueView<List<Brand>>(
        value: list,
        onRetry: () => ref.invalidate(adminBrandsProvider),
        // Пустой список — не повод прятать кнопку «завести марку»:
        // именно с пустого списка её и хочется нажать.
        data: (all) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: all.length + 1,
          itemBuilder: (_, i) => i == 0
              ? _AddBrandTile(existing: all)
              : _BrandCard(brand: all[i - 1], all: all),
        ),
      ),
    );
  }
}

/// Завести марку заранее, не дожидаясь товара с ней.
class _AddBrandTile extends ConsumerWidget {
  const _AddBrandTile({required this.existing});
  final List<Brand> existing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: OutlinedButton.icon(
        onPressed: () => _createBrand(context, ref),
        icon: const Icon(Icons.add, size: 18),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          foregroundColor: c.accent,
          side: BorderSide(color: c.line),
        ),
        label: Text(existing.isEmpty
            ? 'Завести первую марку'
            : 'Завести марку'),
      ),
    );
  }
}

void _createBrand(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Новая марка'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Название',
              hintText: 'Knauf',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Товаров у неё пока не будет — она появится в подсказках, '
            'когда поставщик начнёт заполнять поле «Марка».',
            style: TextStyle(fontSize: 12, color: context.colors.gray),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim();
            Navigator.pop(dialogCtx);
            if (name.isEmpty) return;
            _runBrandAction(context, ref, () async {
              await ref.read(adminRepositoryProvider).createBrand(name);
              return 'Марка «$name» заведена';
            });
          },
          child: const Text('Завести'),
        ),
      ],
    ),
  );
}

class _BrandCard extends ConsumerWidget {
  const _BrandCard({required this.brand, required this.all});
  final Brand brand;

  /// Весь список нужен для объединения: выбирать не из чего, если знать
  /// только саму марку.
  final List<Brand> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(brand.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          brand.isEmpty ? 'нет товаров' : _brandProducts(brand.products),
          style: TextStyle(fontSize: 12, color: brand.isEmpty ? c.orange : c.gray),
        ),
        trailing: Icon(Icons.more_horiz, color: c.faint),
        onTap: () => _showBrandActions(context, ref, brand, all),
      ),
    );
  }
}

/// Склонение берём из каталога, а не пишем второе такое же: две копии
/// этой логики неизбежно разъедутся.
String _brandProducts(int n) => '$n ${productsPlural(n)}';

void _showBrandActions(
    BuildContext context, WidgetRef ref, Brand brand, List<Brand> all) {
  showModalBottomSheet(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(brand.name,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Переименовать'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _renameBrand(context, ref, brand);
            },
          ),
          ListTile(
            leading: const Icon(Icons.merge_outlined),
            title: const Text('Объединить с другой'),
            subtitle: const Text('товары переедут, эта марка исчезнет'),
            enabled: all.length > 1,
            onTap: () {
              Navigator.pop(sheetCtx);
              _mergeBrand(context, ref, brand, all);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline,
                color: brand.isEmpty ? context.colors.red : null),
            title: const Text('Удалить'),
            // База откажет всё равно, но объяснить причину лучше здесь,
            // чем показывать ошибку после нажатия.
            subtitle: brand.isEmpty
                ? null
                : const Text('нельзя: у марки есть товары'),
            enabled: brand.isEmpty,
            onTap: () {
              Navigator.pop(sheetCtx);
              _deleteBrand(context, ref, brand);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _runBrandAction(
  BuildContext context,
  WidgetRef ref,
  Future<String> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final text = await action();
    ref.invalidate(adminBrandsProvider);
    // Марка видна в карточке товара и в фильтрах каталога — их тоже
    // надо перечитать, иначе останется старое название.
    ref.invalidate(allBrandsProvider);
    messenger.showSnackBar(SnackBar(content: Text(text)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
  }
}

void _renameBrand(BuildContext context, WidgetRef ref, Brand brand) {
  final controller = TextEditingController(text: brand.name);
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Переименовать марку'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Название'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim();
            Navigator.pop(dialogCtx);
            if (name.isEmpty || name == brand.name) return;
            _runBrandAction(context, ref, () async {
              await ref.read(adminRepositoryProvider).renameBrand(brand.id, name);
              return 'Марка переименована в «$name»';
            });
          },
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}

void _mergeBrand(
    BuildContext context, WidgetRef ref, Brand from, List<Brand> all) {
  final others = all.where((b) => b.id != from.id).toList();
  showModalBottomSheet(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('«${from.name}» переедет в:',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Товары сменят марку, а «${from.name}» исчезнет. Отменить '
              'одним действием нельзя.',
              style: TextStyle(fontSize: 12, color: context.colors.gray),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: others.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(others[i].name),
                subtitle: Text(_brandProducts(others[i].products),
                    style: const TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _runBrandAction(context, ref, () async {
                    final n = await ref
                        .read(adminRepositoryProvider)
                        .mergeBrands(from: from.id, into: others[i].id);
                    return n == 0
                        ? 'Марка «${from.name}» удалена, товаров у неё не было'
                        : 'Переехало товаров: $n';
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _deleteBrand(BuildContext context, WidgetRef ref, Brand brand) {
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Удалить марку?'),
      content: Text('«${brand.name}» будет удалена. Товаров у неё нет.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Отмена')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: context.colors.red),
          onPressed: () {
            Navigator.pop(dialogCtx);
            _runBrandAction(context, ref, () async {
              await ref.read(adminRepositoryProvider).deleteBrand(brand.id);
              return 'Марка «${brand.name}» удалена';
            });
          },
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
}
