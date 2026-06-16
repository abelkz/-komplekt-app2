import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/price_drop.dart';

/// История уведомлений о снижении цены (таблица price_drops).
/// RLS отдаёт только записи текущего пользователя.
class NotificationsRepository {
  const NotificationsRepository();

  Future<List<PriceDrop>> list() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      final rows = await supabase
          .from('price_drops')
          .select(
            'id,product_id,product_name,supplier_name,old_price,new_price,status,is_read,created_at',
          )
          .order('created_at', ascending: false)
          .limit(100);
      return rows.map<PriceDrop>((m) => PriceDrop.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить уведомления');
    }
  }

  /// Количество непрочитанных (для бейджа на колоколе).
  Future<int> unreadCount() async {
    if (supabase.auth.currentUser == null) return 0;
    try {
      final rows = await supabase
          .from('price_drops')
          .select('id')
          .eq('is_read', false);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// Отметить все уведомления прочитанными.
  Future<void> markAllRead() async {
    if (supabase.auth.currentUser == null) return;
    try {
      await supabase
          .from('price_drops')
          .update({'is_read': true}).eq('is_read', false);
    } catch (_) {/* не критично */}
  }
}
