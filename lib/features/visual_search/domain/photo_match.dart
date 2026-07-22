import 'dart:ui' show Color;

/// Один материал, распознанный на фотографии интерьера.
class PhotoMaterial {
  const PhotoMaterial({
    required this.title,
    required this.query,
    this.categorySlug,
    this.colorHex,
    this.where = '',
  });

  /// Название для человека: «Керамогранит под бетон»
  final String title;

  /// Готовый запрос для поиска по каталогу
  final String query;

  /// Категория каталога (null — если модель не нашла подходящей)
  final String? categorySlug;

  /// Цвет материала в формате #rrggbb
  final String? colorHex;

  /// Где применён: пол, стена, фартук
  final String where;

  Color? get color {
    final hex = colorHex;
    if (hex == null || !hex.startsWith('#') || hex.length != 7) return null;
    final value = int.tryParse('FF${hex.substring(1)}', radix: 16);
    return value == null ? null : Color(value);
  }

  factory PhotoMaterial.fromMap(Map<String, dynamic> m) {
    final slug = m['category_slug'] as String?;
    return PhotoMaterial(
      title: m['title'] as String? ?? '',
      query: m['query'] as String? ?? '',
      // «other» означает «ни одна категория не подходит»
      categorySlug: (slug == null || slug == 'other') ? null : slug,
      colorHex: m['color_hex'] as String?,
      where: m['where'] as String? ?? '',
    );
  }
}

/// Результат разбора фотографии.
class PhotoMatch {
  const PhotoMatch({
    this.room = '',
    this.style = '',
    this.materials = const [],
  });

  final String room;
  final String style;
  final List<PhotoMaterial> materials;

  factory PhotoMatch.fromMap(Map<String, dynamic> m) => PhotoMatch(
        room: m['room'] as String? ?? '',
        style: m['style'] as String? ?? '',
        materials: (m['materials'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(PhotoMaterial.fromMap)
                .where((x) => x.query.isNotEmpty)
                .toList() ??
            const [],
      );
}
