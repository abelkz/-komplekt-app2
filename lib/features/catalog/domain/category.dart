/// Категория материалов (таблица categories).
class Category {
  const Category({
    required this.slug,
    required this.name,
    this.icon,
    this.imageUrl,
    this.sort = 0,
  });

  final String slug;
  final String name;
  final String? icon;

  /// Фотография материала для крупной плитки на главной (миграция 0028).
  ///
  /// Может отсутствовать — тогда плитка показывает иконку водяным знаком.
  /// Сделано именно так, а не «нет фото — нет плитки»: каталог не должен
  /// разваливаться из-за незаполненного контента.
  final String? imageUrl;

  final int sort;

  /// В живой базе колонка называется `emoji`, в схеме Flutter-миграций —
  /// `icon`. Принимаем оба варианта, чтобы категории грузились в любой базе.
  factory Category.fromMap(Map<String, dynamic> m) => Category(
        slug: m['slug'] as String,
        name: m['name'] as String? ?? '',
        icon: (m['icon'] ?? m['emoji']) as String?,
        imageUrl: m['image_url'] as String?,
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );
}
