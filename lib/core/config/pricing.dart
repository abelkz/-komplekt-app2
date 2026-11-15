import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Скрывать ли покупки внутри приложения.
///
/// Оба магазина требуют продавать цифровые услуги только через свою
/// оплату: App Store — через In-App Purchase (правило 3.1.1), Google
/// Play — через Play Billing (правило «Платежи»). Подписка «Про» и буст —
/// именно цифровые услуги, а платим мы через CloudPayments. Пока своя
/// оплата магазинов не подключена, в мобильных сборках кнопки оплаты
/// скрыты — иначе приложение отклонят.
///
/// Android добавлен вместе с выходом в Google Play. Отладочный APK с
/// GitHub собирается из того же кода, поэтому покупки скрыты и в нём;
/// потери тут нет — функция `create-payment` на сервере всё равно ещё
/// не развёрнута, и оплата не работала бы нигде.
///
/// На вебе оплата через CloudPayments остаётся как была.
bool get iapPurchasesHidden =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// Единственное место с ценами тарифов и бустов на стороне приложения.
///
/// Это цены для ПОКАЗА. Реальную сумму к оплате считает сервер
/// (Edge Function create-payment) — там свой такой же прайс, потому что
/// клиенту доверять сумму нельзя. При изменении цен правим оба места:
/// здесь (что видит человек) и в supabase/functions/create-payment/index.ts
/// (что реально спишется).
class Pricing {
  Pricing._();

  /// Подписка «КОМПЛЕКТ Про» для клиента, ₸/мес.
  static const clientPro = 4900;

  /// Тариф «Про» для поставщика, ₸/мес.
  static const supplierPro = 9900;

  /// Буст (продвижение товара): срок в днях -> цена в ₸.
  static const boost = <int, int>{1: 1500, 3: 3500, 7: 7000};

  /// Доступные сроки буста по возрастанию.
  static List<int> get boostDays => boost.keys.toList()..sort();
}
