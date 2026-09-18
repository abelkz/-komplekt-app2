import '../config/env.dart';
import '../config/supabase_client.dart';

/// Продуктовая аналитика: что люди ищут, какие категории открывают, где
/// отваливаются. Пишет в таблицу `app_events` (миграция 0024).
///
/// Отличие от EventsRepository: тот считает просмотры и контакты для
/// статистики конкретного поставщика. Здесь — события всего приложения,
/// в том числе от гостей, у которых аккаунта ещё нет.
///
/// Правила: никогда не ломает экран (ошибки проглатываются), ничего не ждёт
/// (вызывается без await) и молчит в демо-режиме, где базы нет.
class Analytics {
  Analytics._();

  /// Названия событий держим в одном месте, чтобы в базе не расползались
  /// опечатки вроде `search` / `Search` / `searh`.
  static const search = 'search';
  static const productView = 'product_view';
  static const categoryOpen = 'category_open';
  static const contactSupplier = 'contact_supplier';

  static void log(String name, [Map<String, dynamic> props = const {}]) {
    if (Env.demoMode) return;
    // Намеренно не ждём результат: аналитика не должна задерживать переход
    // между экранами и тем более отменять его при ошибке сети.
    _send(name, props);
  }

  static Future<void> _send(String name, Map<String, dynamic> props) async {
    try {
      await supabase.from('app_events').insert({
        'user_id': supabase.auth.currentUser?.id,
        'name': name,
        'props': props,
      });
    } catch (_) {
      // Молча: упавшая статистика не повод показывать что-то пользователю.
    }
  }
}
