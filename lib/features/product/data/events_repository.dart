import '../../../core/config/supabase_client.dart';
import '../../catalog/domain/product.dart';

/// Логирование событий для статистики поставщиков (через RPC log_event).
/// Ошибки намеренно проглатываются — статистика не должна ломать UX.
class EventsRepository {
  const EventsRepository();

  /// Просмотр карточки засчитывается каждому поставщику товара.
  Future<void> logView(Product product) async {
    for (final o in product.offers) {
      final sid = o.supplierId;
      if (sid == null) continue;
      try {
        await supabase.rpc('log_event', params: {
          'p_product': product.id,
          'p_supplier': sid,
          'p_type': 'view',
        });
      } catch (_) {/* игнорируем */}
    }
  }

  Future<void> logContact(String productId, String? supplierId) async {
    if (supplierId == null) return;
    try {
      await supabase.rpc('log_event', params: {
        'p_product': productId,
        'p_supplier': supplierId,
        'p_type': 'contact',
      });
    } catch (_) {/* игнорируем */}
  }
}
