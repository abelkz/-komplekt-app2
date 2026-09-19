import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';
import '../admin_providers.dart';

/// Что можно сделать с компанией: заблокировать на срок, снять блокировку,
/// удалить.
///
/// Блокировка — это не отказ в заявке. Компания остаётся одобренной, её
/// данные целы, она просто не показывается покупателям до указанной даты.
/// Срок снимается сам: «на две недели» не требует, чтобы кто-то вспомнил
/// про неё через две недели.
Future<void> showSupplierActions(BuildContext context, SupplierRow s) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SupplierActionsSheet(supplier: s),
  );
}

class _SupplierActionsSheet extends ConsumerStatefulWidget {
  const _SupplierActionsSheet({required this.supplier});
  final SupplierRow supplier;

  @override
  ConsumerState<_SupplierActionsSheet> createState() =>
      _SupplierActionsSheetState();
}

class _SupplierActionsSheetState extends ConsumerState<_SupplierActionsSheet> {
  final _reason = TextEditingController();

  /// Срок блокировки в днях. null — бессрочно.
  int? _days = 14;
  bool _forever = false;
  bool _busy = false;
  String? _error;

  static const _terms = {3: '3 дня', 7: 'Неделя', 14: '2 недели', 30: 'Месяц'};

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  SupplierRow get s => widget.supplier;

  /// Все действия ходят через один обработчик: он держит «занято», ловит
  /// ошибку и обновляет список. Без этого каждая кнопка обрастала бы
  /// собственным setState и однажды разошлась бы с соседней.
  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await action();
      ref.invalidate(adminSupplierStatsProvider);
      ref.invalidate(adminOverviewProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      final t = e.toString();
      setState(() {
        _busy = false;
        _error = t.startsWith('Failure: ') ? t.substring(9) : t;
      });
    }
  }

  Future<void> _block() => _run(() async {
        await ref.read(adminRepositoryProvider).blockSupplier(
              s.id,
              days: _forever ? null : _days,
              reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
            );
        return _forever
            ? '«${s.name}» скрыта бессрочно'
            : '«${s.name}» скрыта на ${_terms[_days] ?? '$_days дн.'}';
      });

  Future<void> _unblock() => _run(() async {
        await ref.read(adminRepositoryProvider).unblockSupplier(s.id);
        return '«${s.name}» снова в каталоге';
      });

  Future<void> _delete() async {
    // Удаление необратимо, поэтому подтверждение — не «вы уверены?», а ввод
    // названия компании. Промахнуться мимо кнопки можно, набрать название
    // чужой компании случайно — нет.
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDeleteDialog(supplier: s),
    );
    if (ok != true) return;
    await _run(() async {
      final removed =
          await ref.read(adminRepositoryProvider).deleteSupplier(s.id);
      return 'Компания удалена, цен снято: $removed';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.name.isEmpty ? 'Без названия' : s.name,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 4),
            Text(
              [
                if (s.city.isNotEmpty) s.city,
                '${s.products} товаров',
                '${s.offers} цен',
                '${s.contacts} обращений',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: c.gray),
            ),
            const SizedBox(height: 18),

            if (s.isBlocked) ..._blockedBlock(c) else ..._blockForm(c),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(fontSize: 13, color: c.red)),
            ],

            const SizedBox(height: 22),
            Divider(height: 1, color: c.line),
            const SizedBox(height: 14),

            // Удаление отделено чертой и уведено вниз: это не рядовое
            // действие в одном ряду с остальными.
            TextButton.icon(
              onPressed: _busy ? null : _delete,
              icon: Icon(Icons.delete_forever, size: 18, color: c.red),
              label: Text('Удалить компанию',
                  style: TextStyle(color: c.red, fontWeight: FontWeight.w600)),
            ),
            Text(
              'Компания и её ${s.offers} цен исчезнут. Карточки товаров '
              'останутся: на них ссылаются цены других поставщиков.',
              style: TextStyle(fontSize: 11, color: c.faint, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────── уже заблокирована ───────────────────

  List<Widget> _blockedBlock(AppColors c) => [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: c.red),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.blockedForever
                    ? 'Скрыта бессрочно'
                    : 'Скрыта до ${_dateLabel(s.blockedUntil!)}',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: c.red),
              ),
              if (s.blockReason != null && s.blockReason!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(s.blockReason!,
                    style: TextStyle(fontSize: 13, color: c.gray)),
              ],
              const SizedBox(height: 8),
              Text(
                'Цены компании не видны покупателям. Сама компания их видит '
                'и знает причину.',
                style: TextStyle(fontSize: 11, color: c.faint, height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _unblock,
            child: Text(_busy ? 'Минуту…' : 'Вернуть в каталог'),
          ),
        ),
      ];

  // ─────────────────── форма блокировки ───────────────────

  List<Widget> _blockForm(AppColors c) => [
        Text('НА КАКОЙ СРОК',
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: c.faint)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in _terms.entries)
              _Pill(
                label: e.value,
                selected: !_forever && _days == e.key,
                onTap: () => setState(() {
                  _forever = false;
                  _days = e.key;
                }),
              ),
            _Pill(
              label: 'Бессрочно',
              selected: _forever,
              onTap: () => setState(() => _forever = true),
            ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _reason,
          decoration: const InputDecoration(
            labelText: 'Причина',
            hintText: 'Штраф, жалобы на цены, неответ на звонки…',
            helperText: 'Поставщик увидит её у себя в кабинете',
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: c.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _busy ? null : _block,
            icon: const Icon(Icons.block, size: 18),
            label: Text(_busy ? 'Минуту…' : 'Скрыть из каталога'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Цены компании перестанут показываться покупателям. Данные и '
          'товары сохранятся, срок снимется сам.',
          style: TextStyle(fontSize: 11, color: c.faint, height: 1.35),
        ),
      ];
}

/// Подтверждение удаления вводом названия компании.
class _ConfirmDeleteDialog extends StatefulWidget {
  const _ConfirmDeleteDialog({required this.supplier});
  final SupplierRow supplier;

  @override
  State<_ConfirmDeleteDialog> createState() => _ConfirmDeleteDialogState();
}

class _ConfirmDeleteDialogState extends State<_ConfirmDeleteDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  /// Сравниваем без учёта регистра и лишних пробелов: смысл подтверждения —
  /// убедиться, что человек смотрит на нужную компанию, а не проверить,
  /// как он попадает по клавишам.
  bool get _match =>
      _typed.text.trim().toLowerCase() ==
      widget.supplier.name.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: const Text('Удалить компанию?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Будет удалена компания и ${widget.supplier.offers} её цен. '
            'Отменить это нельзя.',
            style: TextStyle(fontSize: 13, color: c.gray, height: 1.35),
          ),
          const SizedBox(height: 14),
          Text('Введите название, чтобы подтвердить:',
              style: TextStyle(fontSize: 12, color: c.faint)),
          const SizedBox(height: 6),
          Text(widget.supplier.name,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _typed,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(isDense: true),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.red),
          onPressed: _match ? () => Navigator.pop(context, true) : null,
          child: const Text('Удалить'),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? c.ink : c.card,
          border: Border.all(color: selected ? c.ink : c.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? c.paper : c.ink)),
      ),
    );
  }
}

String _dateLabel(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.${d.year}';
