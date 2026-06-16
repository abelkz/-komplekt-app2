import 'dart:ui' show Color;

import 'offer.dart';

/// Фото товара (таблица product_images).
class ProductImage {
  const ProductImage({required this.url, this.sort = 0});
  final String url;
  final int sort;

  factory ProductImage.fromMap(Map<String, dynamic> m) => ProductImage(
        url: m['url'] as String? ?? '',
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );
}

/// Товар каталога с вложенными предложениями и фото.
class Product {
  const Product({
    required this.id,
    required this.name,
    this.categorySlug,
    this.brand = '',
    this.sku = '',
    this.unit = 'шт',
    this.color,
    this.description,
    this.rating = 0,
    this.images = const [],
    this.offers = const [],
  });

  final String id;
  final String name;
  final String? categorySlug;
  final String brand;
  final String sku;
  final String unit;
  final String? color; // hex для заглушки-фона
  final String? description;
  final double rating;
  final List<ProductImage> images;
  final List<Offer> offers;

  // ── Вычисляемые поля для UI (как в прототипе) ──

  List<Offer> get sortedOffers =>
      [...offers]..sort((a, b) => a.price.compareTo(b.price));

  double? get minPrice =>
      offers.isEmpty ? null : offers.map((o) => o.price).reduce((a, b) => a < b ? a : b);

  double? get maxPrice =>
      offers.isEmpty ? null : offers.map((o) => o.price).reduce((a, b) => a > b ? a : b);

  int get offersCount => offers.length;

  /// Процент экономии «лучшая цена против самой высокой».
  int get savingPercent {
    final mn = minPrice, mx = maxPrice;
    if (mn == null || mx == null || mx == 0 || mn == mx) return 0;
    return ((1 - mn / mx) * 100).round();
  }

  /// Лучшее (самое дешёвое) предложение.
  Offer? get bestOffer => offers.isEmpty ? null : sortedOffers.first;

  /// Первое фото из галереи (или null — тогда показываем заглушку).
  String? get primaryImageUrl {
    if (images.isEmpty) return null;
    final sorted = [...images]..sort((a, b) => a.sort.compareTo(b.sort));
    return sorted.first.url;
  }

  /// Цвет-заглушка по hex из поля color.
  Color? get placeholderColor {
    final hex = color;
    if (hex == null || !hex.startsWith('#') || hex.length != 7) return null;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  factory Product.fromMap(Map<String, dynamic> m) {
    // brand может прийти как строка или как вложенный объект brands(name)
    String brand = '';
    final rawBrand = m['brand'];
    if (rawBrand is String) {
      brand = rawBrand;
    } else if (m['brands'] is Map) {
      brand = (m['brands']['name'] as String?) ?? '';
    }

    return Product(
      id: m['id'].toString(),
      name: m['name'] as String? ?? '',
      categorySlug: m['category_slug'] as String?,
      brand: brand,
      sku: m['sku'] as String? ?? '',
      unit: m['unit'] as String? ?? 'шт',
      color: m['color'] as String?,
      description: m['description'] as String?,
      rating: (m['rating'] as num?)?.toDouble() ?? 0,
      images: (m['product_images'] as List?)
              ?.map((e) => ProductImage.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
      offers: (m['offers'] as List?)
              ?.map((e) => Offer.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
