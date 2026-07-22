/// Отзыв на товар (таблица reviews + join users.full_name).
class Review {
  const Review({
    required this.id,
    required this.rating,
    this.text,
    this.authorName = 'Пользователь',
    this.createdAt,
  });

  final String id;
  final int rating; // 1..5
  final String? text;
  final String authorName;
  final DateTime? createdAt;

  factory Review.fromMap(Map<String, dynamic> m) {
    final user = m['profiles'] ?? m['users'];
    final author =
        user is Map<String, dynamic> ? (user['full_name'] as String?) : null;
    return Review(
      id: m['id'].toString(),
      rating: (m['rating'] as num?)?.toInt() ?? 0,
      text: m['text'] as String?,
      authorName: (author == null || author.isEmpty) ? 'Пользователь' : author,
      createdAt: m['created_at'] != null
          ? DateTime.tryParse(m['created_at'].toString())
          : null,
    );
  }
}
