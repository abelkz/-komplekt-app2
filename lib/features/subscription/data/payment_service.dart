import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../../../core/utils/launchers.dart';

/// Онлайн-оплата через CloudPayments.
///
/// Приложение просит серверную функцию create-payment создать счёт и
/// возвращает ссылку на страницу оплаты (карта / Apple Pay / Google Pay).
/// Открываем её в браузере; включение тарифа/бустов делает вебхук после
/// подтверждения оплаты.
class PaymentService {
  const PaymentService();

  /// Создаёт счёт и открывает страницу оплаты. Возвращает id платежа —
  /// по нему приложение потом проверит статус.
  Future<String> pay({
    required String kind, // pro_client | pro_supplier | boost
    int months = 1,
    int boostDays = 1,
    int boostQty = 1,
    String? supplierId,
  }) async {
    try {
      final res = await supabase.functions.invoke('create-payment', body: {
        'kind': kind,
        'months': months,
        'boost_days': boostDays,
        'boost_qty': boostQty,
        if (supplierId != null) 'supplier_id': supplierId,
      });

      final data = res.data;
      if (data is Map && data['url'] is String) {
        await Launchers.website(data['url'] as String);
        return data['paymentId']?.toString() ?? '';
      }
      final msg = (data is Map ? data['error'] : null)?.toString();
      throw Failure(msg ?? 'Не удалось создать оплату');
    } on Failure {
      rethrow;
    } catch (e) {
      // Функция ещё не развёрнута или сеть — сообщаем понятно
      if (e.toString().contains('create-payment') ||
          e.toString().contains('FunctionException')) {
        throw const Failure('Онлайн-оплата ещё не подключена');
      }
      throw mapError(e, fallback: 'Не удалось создать оплату');
    }
  }

  /// Статус платежа: new / paid / failed. Для проверки после возврата.
  Future<String?> status(String paymentId) async {
    if (paymentId.isEmpty) return null;
    try {
      final row = await supabase
          .from('payments')
          .select('status')
          .eq('id', paymentId)
          .maybeSingle();
      return row?['status'] as String?;
    } catch (_) {
      return null;
    }
  }
}

final paymentServiceProvider = Provider((ref) => const PaymentService());
