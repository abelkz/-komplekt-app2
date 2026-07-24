import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';

/// Одно изменение цены у одного поставщика.
class PricePoint {
  const PricePoint({
    required this.price,
    required this.at,
    this.supplier = '',
  });

  final double price;
  final DateTime at;
  final String supplier;

  factory PricePoint.fromMap(Map<String, dynamic> m) => PricePoint(
        price: (m['price'] as num).toDouble(),
        at: DateTime.parse(m['changed_at'] as String).toLocal(),
        supplier: (m['suppliers'] as Map?)?['name'] as String? ?? '',
      );
}

/// История цен товара. Доступна по тарифу — политика в базе просто
/// вернёт пустой список тому, у кого тарифа нет.
class PriceHistoryRepository {
  const PriceHistoryRepository();

  Future<List<PricePoint>> forProduct(String productId,
      {int days = 180}) async {
    try {
      final since = DateTime.now().subtract(Duration(days: days));
      final rows = await supabase
          .from('price_history')
          .select('price,changed_at,suppliers(name)')
          .eq('product_id', productId)
          .gte('changed_at', since.toUtc().toIso8601String())
          .order('changed_at');
      return rows.map<PricePoint>((m) => PricePoint.fromMap(m)).toList();
    } catch (e) {
      // Таблицы ещё нет (миграция 0018) — история просто не показывается
      if (e.toString().contains('price_history')) return const [];
      throw mapError(e, fallback: 'Не удалось загрузить историю цен');
    }
  }
}

final priceHistoryRepositoryProvider =
    Provider((ref) => const PriceHistoryRepository());

final priceHistoryProvider =
    FutureProvider.family<List<PricePoint>, String>((ref, productId) =>
        ref.read(priceHistoryRepositoryProvider).forProduct(productId));
