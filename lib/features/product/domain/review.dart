/// Отзыв на товар (таблица reviews + join users.full_name).
class Review {
  const Review({
    required this.id,
    required this.rating,
    this.text,
    this.authorName = 'Пользователь',
    this.authorId,
    this.createdAt,
  });

  final String id;
  final int rating; // 1..5
  final String? text;
  final String authorName;

  /// id автора (reviews.user_id) — нужен, чтобы скрыть все отзывы этого
  /// пользователя (модерация пользовательского контента).
  final String? authorId;
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
      authorId: m['user_id']?.toString(),
      createdAt: m['created_at'] != null
          ? DateTime.tryParse(m['created_at'].toString())
          : null,
    );
  }
}
