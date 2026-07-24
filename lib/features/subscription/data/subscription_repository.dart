import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';

/// Кому предназначен тариф.
enum PlanKind { client, supplier }

/// Заявки на платный тариф.
///
/// Приём платежей внутри приложения пока не подключён, поэтому «Оформить»
/// оставляет заявку, а дальше с человеком связываются и включают тариф
/// вручную. Когда появится эквайринг, здесь же будет и оплата.
class SubscriptionRepository {
  const SubscriptionRepository();

  Future<void> request({
    required PlanKind kind,
    String? supplierId,
    String? contact,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw const Failure('Войдите, чтобы оформить подписку');
    try {
      await supabase.from('subscription_requests').insert({
        'user_id': uid,
        'kind': kind == PlanKind.client ? 'client' : 'supplier',
        if (supplierId != null) 'supplier_id': int.tryParse(supplierId),
        if (contact != null && contact.isNotEmpty) 'contact': contact,
      });
    } catch (e) {
      // Таблицы ещё нет (миграция 0015) — не мешаем человеку написать нам
      if (e.toString().contains('subscription_requests')) return;
      throw mapError(e, fallback: 'Не удалось отправить заявку');
    }
  }
}
