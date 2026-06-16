/// Уведомление о снижении цены (строка таблицы price_drops).
class PriceDrop {
  const PriceDrop({
    required this.id,
    this.productId,
    this.productName = '',
    this.supplierName = '',
    this.oldPrice = 0,
    this.newPrice = 0,
    this.status = 'sent',
    this.isRead = false,
    this.createdAt,
  });

  final String id;
  final String? productId;
  final String productName;
  final String supplierName;
  final double oldPrice;
  final double newPrice;
  final String status; // pending | sent | error
  final bool isRead;
  final DateTime? createdAt;

  /// Процент снижения (старая → новая цена).
  int get discountPercent {
    if (oldPrice <= 0 || newPrice >= oldPrice) return 0;
    return ((oldPrice - newPrice) / oldPrice * 100).round();
  }

  factory PriceDrop.fromMap(Map<String, dynamic> m) => PriceDrop(
        id: m['id'].toString(),
        productId: m['product_id']?.toString(),
        productName: m['product_name'] as String? ?? '',
        supplierName: m['supplier_name'] as String? ?? '',
        oldPrice: (m['old_price'] as num?)?.toDouble() ?? 0,
        newPrice: (m['new_price'] as num?)?.toDouble() ?? 0,
        status: m['status'] as String? ?? 'sent',
        isRead: m['is_read'] as bool? ?? false,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'].toString())
            : null,
      );
}
