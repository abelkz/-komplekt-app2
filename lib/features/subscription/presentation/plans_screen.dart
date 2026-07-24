import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/contacts.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/launchers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/payment_service.dart';
import '../data/subscription_repository.dart';

/// Экран 13 — платный тариф.
///
/// Два разных предложения по одному адресу: клиентам (дизайнерам,
/// прорабам) и поставщикам. Что показать — определяет параметр `for`
/// в ссылке.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key, required this.kind, this.supplierId});

  final PlanKind kind;

  /// Компания поставщика — попадёт в заявку, чтобы не выяснять её потом
  final String? supplierId;

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  bool _sending = false;

  bool get _forSupplier => widget.kind == PlanKind.supplier;

  // Цены вынесены сюда, чтобы менялись в одном месте
  static const _clientPrice = 4900;
  static const _supplierPrice = 9900;

  List<(IconData, String, String)> get _features => _forSupplier
      ? const [
          (
            Icons.trending_up,
            'Продвижение товаров',
            'Поднимайте свои позиции в топ категорий и поиска. '
                'В карточке стоит пометка «продвигается» — покупатель '
                'видит, что это реклама.'
          ),
          (
            Icons.verified_outlined,
            'Проверка компании',
            'Мы смотрим свидетельство ИП или ТОО и ставим значок '
                '«проверенная компания» рядом с вашими ценами.'
          ),
          (
            Icons.bar_chart,
            'Статистика спроса',
            'Сколько раз смотрели ваш товар и сколько раз обращались '
                'к вам по нему.'
          ),
          (
            Icons.upload_file,
            'Прайс без ограничений',
            'Загружайте прайс любого объёма и обновляйте цены '
                'сколько нужно.'
          ),
          (
            Icons.support_agent,
            'Разбор прайса',
            'Поможем сопоставить колонки и артикулы при первой загрузке.'
          ),
        ]
      : const [
          (
            Icons.picture_as_pdf_outlined,
            'Спецификации с вашим логотипом',
            'PDF для клиента с вашими реквизитами вместо наших.'
          ),
          (
            Icons.show_chart,
            'История цен',
            'Видно, как менялась цена у каждого поставщика — понятно, '
                'когда закупаться.'
          ),
          (
            Icons.layers_outlined,
            'Подборки без ограничений',
            'Сколько угодно объектов и позиций в каждом.'
          ),
          (
            Icons.notifications_active_outlined,
            'Уведомления с любым порогом',
            'Ловите снижение цены хоть от одного процента.'
          ),
        ];

  Future<void> _order() async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);

    // Сначала пробуем онлайн-оплату картой/Apple Pay/Google Pay
    try {
      await ref.read(paymentServiceProvider).pay(
            kind: _forSupplier ? 'pro_supplier' : 'pro_client',
            months: 1,
            supplierId: widget.supplierId,
          );
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(const SnackBar(
          content: Text('Открыли оплату — тариф включится сразу после оплаты')));
      return;
    } catch (e) {
      final t = e.toString();
      final notReady = t.contains('не подключена');
      if (!notReady) {
        if (!mounted) return;
        setState(() => _sending = false);
        messenger.showSnackBar(SnackBar(
            content: Text(t.startsWith('Failure: ') ? t.substring(9) : 'Ошибка оплаты')));
        return;
      }
      // Онлайн-оплата ещё не развёрнута — откатываемся на заявку + WhatsApp
    }

    await _orderViaManager(messenger);
  }

  /// Запасной путь, пока онлайн-оплата не подключена: заявка + WhatsApp.
  Future<void> _orderViaManager(ScaffoldMessengerState messenger) async {
    final profile = ref.read(myProfileProvider).valueOrNull;
    var saved = true;
    try {
      await ref.read(subscriptionRepositoryProvider).request(
            kind: widget.kind,
            supplierId: widget.supplierId,
            contact: profile?.phone,
          );
    } catch (_) {
      saved = false;
    }
    final what =
        _forSupplier ? 'тариф Pro для поставщика' : 'подписку КОМПЛЕКТ Pro';
    final who = profile?.company.isNotEmpty == true
        ? profile!.company
        : (profile?.fullName ?? '');
    await Launchers.whatsapp(
      Contacts.whatsapp,
      text: 'Здравствуйте! Хочу оформить $what.'
          '${who.isEmpty ? '' : ' Компания: $who.'}',
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (saved) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Заявка отправлена — свяжемся и подключим тариф')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final price = _forSupplier ? _supplierPrice : _clientPrice;

    return Scaffold(
      appBar: AppBar(
          title: Text(_forSupplier ? 'Тариф Pro' : 'КОМПЛЕКТ Pro')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.orangeSoft,
              border: Border.all(color: c.orange.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_forSupplier ? '★ ТАРИФ PRO' : '★ КОМПЛЕКТ PRO',
                    style: AppTypography.sectionLabel(color: c.orange)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Formatters.price(price),
                        style: AppTypography.unbounded(size: 30, color: c.orange)),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text('в месяц',
                          style: TextStyle(fontSize: 13, color: c.orange)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _forSupplier
                      ? 'Для компаний, которые продают материалы через КОМПЛЕКТ.'
                      : 'Для дизайнеров, комплектаторов и прорабов.',
                  style: TextStyle(fontSize: 13, color: c.orange, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          Text('ЧТО ВХОДИТ', style: AppTypography.sectionLabel(color: c.gray)),
          const SizedBox(height: 12),
          for (final (icon, title, text) in _features)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: c.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(text,
                            style: TextStyle(
                                fontSize: 13, color: c.gray, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          if (_forSupplier) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: c.line)),
              child: Text(
                'Оплата не влияет на порядок цен. В шкале цен внутри товара '
                'первым всегда идёт тот, у кого дешевле — иначе сравнение '
                'цен перестало бы быть сравнением цен.',
                style: TextStyle(fontSize: 12, color: c.gray, height: 1.45),
              ),
            ),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _sending ? null : _order,
              child: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.brandInk))
                  : const Text('Оформить'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Оплата картой, Apple Pay или Google Pay через CloudPayments. '
            'Тариф включается сразу после оплаты.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.faint, height: 1.4),
          ),
        ],
      ),
    );
  }
}
