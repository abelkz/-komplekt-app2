import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Скрывать ли покупки внутри приложения.
///
/// На iOS App Store требует продавать цифровые услуги только через Apple
/// In-App Purchase (правило 3.1.1). Пока IAP не подключён — в iOS-сборке
/// кнопки оплаты (тариф Pro, бусты) скрыты, иначе приложение отклонят.
/// На вебе и Android оплата через CloudPayments работает как прежде.
/// Когда подключим Apple IAP — заменим это на нормальную покупку.
bool get iapPurchasesHidden =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

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
