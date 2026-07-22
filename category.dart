/// Категория материалов (таблица categories).
class Category {
  const Category({
    required this.slug,
    required this.name,
    this.icon,
    this.sort = 0,
  });

  final String slug;
  final String name;
  final String? icon;
  final int sort;

  /// В живой базе колонка называется `emoji`, в схеме Flutter-миграций —
  /// `icon`. Принимаем оба варианта, чтобы категории грузились в любой базе.
  factory Category.fromMap(Map<String, dynamic> m) => Category(
        slug: m['slug'] as String,
        name: m['name'] as String? ?? '',
        icon: (m['icon'] ?? m['emoji']) as String?,
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );
}
