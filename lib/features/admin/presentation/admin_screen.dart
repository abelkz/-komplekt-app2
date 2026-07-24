import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/launchers.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../auth/domain/app_user.dart';
import '../data/admin_repository.dart';
import 'admin_providers.dart';

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
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Панель'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Поставщики'),
            Tab(text: 'Тарифы'),
          ]),
        ),
        body: const TabBarView(children: [_SuppliersTab(), _PlansTab()]),
      ),
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
        if (u.phone != null && u.phone!.isNotEmpty) ...[
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
        if (who?.phone != null && who!.phone!.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ContactRow(phone: who.phone!),
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

// ──────────────────────────── Общее ────────────────────────────

String _msg(Object e) {
  final t = e.toString();
  return t.startsWith('Failure: ') ? t.substring(9) : 'Не получилось';
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

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
