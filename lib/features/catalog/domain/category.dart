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

  factory Category.fromMap(Map<String, dynamic> m) => Category(
        slug: m['slug'] as String,
        name: m['name'] as String? ?? '',
        icon: m['icon'] as String?,
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );
}
