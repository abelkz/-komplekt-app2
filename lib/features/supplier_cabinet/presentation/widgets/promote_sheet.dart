import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/pricing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../subscription/data/payment_service.dart';
import '../../data/supplier_cabinet_repository.dart';
import '../supplier_cabinet_providers.dart';

/// Лист «Поднять в топ».
///
/// Сначала предлагаем бесплатные подъёмы Pro (пока есть месячная норма),
/// затем купленные кредиты Буста по срокам. Если ничего нет — ведём
/// на покупку Буста.
Future<void> showPromoteSheet(BuildContext context, String offerId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PromoteSheet(offerId: offerId),
  );
}

class _PromoteSheet extends ConsumerWidget {
  const _PromoteSheet({required this.offerId});
  final String offerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final status = ref.watch(boostStatusProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        child: status.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              e.toString().replaceFirst('Failure: ', ''),
              style: TextStyle(color: c.gray),
            ),
          ),
          data: (s) => _content(context, ref, c, s),
        ),
      ),
    );
  }

  Widget _content(
      BuildContext context, WidgetRef ref, AppColors c, BoostStatus s) {
    final options = <Widget>[];

    // Бесплатные подъёмы Pro (1 и 3 дня)
    if (s.isPro && s.freeLeft > 0) {
      for (final d in [1, 3]) {
        options.add(_Option(
          title: '$d ${_dayWord(d)} · бесплатно',
          subtitle: 'по тарифу Pro, осталось ${s.freeLeft} в этом месяце',
          accent: true,
          onTap: () => _promote(context, ref, d),
        ));
      }
    }

    // Купленные кредиты по срокам
    for (final d in [1, 3, 7]) {
      final n = s.creditsFor(d);
      if (n > 0) {
        options.add(_Option(
          title: '$d ${_dayWord(d)} · Буст',
          subtitle: 'куплено: $n',
          onTap: () => _promote(context, ref, d),
        ));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Поднять в топ',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Ваше предложение покажется отдельной строкой сверху категории и '
          'поиска — с вашим именем и ценой, с пометкой «продвигается». '
          'Конкуренты в этой строке не показываются.',
          style: TextStyle(fontSize: 12, color: c.gray, height: 1.35),
        ),
        const SizedBox(height: 14),
        if (options.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              s.isPro
                  ? 'Бесплатные подъёмы на этот месяц закончились. '
                      'Купите Буст, чтобы поднять сейчас или на 7 дней.'
                  : 'Подъём в топ — по Бусту. Купите подъём на 1, 3 или 7 дней.',
              style: TextStyle(fontSize: 13, color: c.ink, height: 1.35),
            ),
          )
        else
          ...options,
        // На iOS покупка буста скрыта, пока не подключён Apple IAP
        // (иначе App Store отклонит). На вебе/Android — как прежде.
        if (!iapPurchasesHidden) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.ink,
              side: BorderSide(color: c.line),
              minimumSize: const Size.fromHeight(46),
            ),
            icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
            label: const Text('Купить Буст'),
            onPressed: () {
              Navigator.pop(context);
              showBuyBoostSheet(context);
            },
          ),
        ],
      ],
    );
  }

  Future<void> _promote(BuildContext context, WidgetRef ref, int days) async {
    final messenger = ScaffoldMessenger.of(context);
    final until = await ref
        .read(cabinetControllerProvider.notifier)
        .promoteOffer(offerId, days: days);
    if (context.mounted) Navigator.pop(context);
    if (until != null) {
      messenger.showSnackBar(SnackBar(
          content: Text('Товар в топе до ${until.day}.${until.month}')));
    } else {
      final e = ref.read(cabinetControllerProvider).error;
      final t = e?.toString() ?? '';
      messenger.showSnackBar(SnackBar(
          content: Text(t.startsWith('Failure: ')
              ? t.substring(9)
              : 'Не удалось продвинуть')));
    }
  }

  static String _dayWord(int d) => d == 1 ? 'день' : 'дня';
}

class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = false,
  });
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent ? c.orangeSoft : c.card,
            border: Border.all(color: accent ? c.orange : c.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: accent ? c.orange : c.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 12, color: c.gray)),
                  ],
                ),
              ),
              Icon(Icons.arrow_upward, size: 18, color: c.orange),
            ],
          ),
        ),
      ),
    );
  }
}

/// Лист покупки Буста: срок и количество подъёмов. Оставляет заявку —
/// оплата подтверждается вручную, после чего кредиты появляются в кабинете.
Future<void> showBuyBoostSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _BuyBoostSheet(),
  );
}

class _BuyBoostSheet extends ConsumerStatefulWidget {
  const _BuyBoostSheet();
  @override
  ConsumerState<_BuyBoostSheet> createState() => _BuyBoostSheetState();
}

class _BuyBoostSheetState extends ConsumerState<_BuyBoostSheet> {
  int _days = 3;
  int _qty = 1;
  bool _busy = false;

  // Цена Буста — из единой настройки Pricing
  int get _total => (Pricing.boost[_days] ?? 0) * _qty;

  static String _tg(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return '$b ₸';
  }

  Future<void> _order() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    // Сначала онлайн-оплата картой/Apple Pay/Google Pay
    try {
      await ref.read(paymentServiceProvider).pay(
            kind: 'boost',
            boostDays: _days,
            boostQty: _qty,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(
          content: Text('Открыли оплату — бусты начислятся сразу после оплаты')));
      return;
    } catch (e) {
      final t = e.toString();
      if (!t.contains('не подключена')) {
        if (!mounted) return;
        setState(() => _busy = false);
        messenger.showSnackBar(SnackBar(
            content: Text(t.startsWith('Failure: ') ? t.substring(9) : 'Ошибка оплаты')));
        return;
      }
      // онлайн-оплата не развёрнута — откат на заявку
    }

    final ok = await ref
        .read(cabinetControllerProvider.notifier)
        .orderBoost(days: _days, qty: _qty);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pop(context);
    if (ok) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Заявка на Буст отправлена — подключим и напишем')));
    } else {
      final e = ref.read(cabinetControllerProvider).error;
      final t = e?.toString() ?? '';
      messenger.showSnackBar(SnackBar(
          content: Text(t.startsWith('Failure: ')
              ? t.substring(9)
              : 'Не удалось оформить')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Купить Буст',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Один Буст — это один подъём товара в топ на выбранный срок.',
                style: TextStyle(fontSize: 12, color: c.gray)),
            const SizedBox(height: 16),
            Text('Срок подъёма', style: TextStyle(fontSize: 13, color: c.gray)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final d in Pricing.boostDays)
                  ChoiceChip(
                    label: Text('$d ${d == 1 ? 'день' : 'дней'} · '
                        '${_tg(Pricing.boost[d] ?? 0)}'),
                    selected: _days == d,
                    onSelected: (_) => setState(() => _days = d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Количество', style: TextStyle(fontSize: 13, color: c.gray)),
                const Spacer(),
                IconButton(
                  onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_qty',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                IconButton(
                  onPressed: _qty < 50 ? () => setState(() => _qty++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Итого', style: TextStyle(fontSize: 13, color: c.gray)),
                const Spacer(),
                Text(_tg(_total),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15)),
                onPressed: _busy ? null : _order,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Оформить на ${_tg(_total)}'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Оплата подключается отдельно — после подтверждения подъёмы '
              'появятся в кабинете.',
              style: TextStyle(fontSize: 11, color: c.gray),
            ),
          ],
        ),
      ),
    );
  }
}
