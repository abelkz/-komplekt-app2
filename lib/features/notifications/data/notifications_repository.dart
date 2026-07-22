import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/price_drop.dart';

/// История уведомлений о снижении цены (таблица price_drops).
/// RLS отдаёт только записи текущего пользователя.
class NotificationsRepository {
  const NotificationsRepository();

  static const _columns =
      'id,product_id,product_name,supplier_name,old_price,new_price,status,created_at';

  /// Колонки is_read может не быть в базе (её добавляет миграция 0009).
  /// Один раз обжигаемся — дальше запрашиваем набор без неё, иначе
  /// PostgREST роняет весь запрос и экран показывает «Ошибка».
  static bool _hasIsRead = true;

  Future<List<PriceDrop>> list() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      final rows = await supabase
          .from('price_drops')
          .select(_hasIsRead ? '$_columns,is_read' : _columns)
          .order('created_at', ascending: false)
          .limit(100);
      return rows.map<PriceDrop>((m) => PriceDrop.fromMap(m)).toList();
    } catch (e) {
      if (_hasIsRead && _isMissingIsRead(e)) {
        _hasIsRead = false;
        return list();
      }
      throw mapError(e, fallback: 'Не удалось загрузить уведомления');
    }
  }

  /// Количество непрочитанных (для бейджа на колоколе).
  Future<int> unreadCount() async {
    if (supabase.auth.currentUser == null || !_hasIsRead) return 0;
    try {
      final rows = await supabase
          .from('price_drops')
          .select('id')
          .eq('is_read', false);
      return rows.length;
    } catch (e) {
      if (_isMissingIsRead(e)) _hasIsRead = false;
      return 0;
    }
  }

  /// Отметить все уведомления прочитанными.
  Future<void> markAllRead() async {
    if (supabase.auth.currentUser == null || !_hasIsRead) return;
    try {
      await supabase
          .from('price_drops')
          .update({'is_read': true}).eq('is_read', false);
    } catch (_) {/* не критично */}
  }

  bool _isMissingIsRead(Object e) => e.toString().contains('is_read');
}
