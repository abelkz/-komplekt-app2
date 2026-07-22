import '../../catalog/domain/product.dart';

/// Позиция внутри подборки (таблица collection_items) + резолв товара.
class CollectionItem {
  const CollectionItem({
    required this.id,
    required this.productId,
    required this.qty,
    this.product,
  });

  final String id;
  final String productId;
  final double qty;
  final Product? product;

  CollectionItem copyWith({double? qty, Product? product}) => CollectionItem(
        id: id,
        productId: productId,
        qty: qty ?? this.qty,
        product: product ?? this.product,
      );

  /// Сумма позиции по лучшей цене товара.
  double get sum => (product?.bestOffer?.price ?? 0) * qty;

  factory CollectionItem.fromMap(Map<String, dynamic> m) {
    final prod = m['products'];
    return CollectionItem(
      id: m['id'].toString(),
      productId: m['product_id'].toString(),
      qty: (m['qty'] as num?)?.toDouble() ?? 1,
      product: prod is Map<String, dynamic> ? Product.fromMap(prod) : null,
    );
  }
}

/// Подборка/проект пользователя (таблица collections).
class Collection {
  const Collection({
    required this.id,
    required this.name,
    this.items = const [],
    this.createdAt,
  });

  final String id;
  final String name;
  final List<CollectionItem> items;
  final DateTime? createdAt;

  double get total => items.fold(0, (s, i) => s + i.sum);

  /// Позиции приезжают из таблицы project_items (так она названа в живой
  /// базе). Старое имя collection_items оставлено для совместимости.
  factory Collection.fromMap(Map<String, dynamic> m) => Collection(
        id: m['id'].toString(),
        name: m['name'] as String? ?? 'Мой проект',
        items: ((m['project_items'] ?? m['collection_items']) as List?)
                ?.map((e) => CollectionItem.fromMap(e as Map<String, dynamic>))
                .toList() ??
            const [],
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'].toString())
            : null,
      );
}
