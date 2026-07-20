import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/review.dart';

/// Отзывы на товар.
class ReviewsRepository {
  const ReviewsRepository();

  Future<List<Review>> forProduct(String productId) async {
    try {
      final rows = await supabase
          .from('reviews')
          .select('id,rating,text,created_at,profiles(full_name)')
          .eq('product_id', productId)
          .order('created_at', ascending: false);
      return rows.map<Review>((m) => Review.fromMap(m)).toList();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить отзывы');
    }
  }

  /// Добавить/обновить свой отзыв (один на товар — upsert).
  Future<void> submit({
    required String productId,
    required int rating,
    String? text,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw const Failure('Нужно войти, чтобы оставить отзыв');
    try {
      await supabase.from('reviews').upsert({
        'product_id': productId,
        'user_id': uid,
        'rating': rating,
        'text': text,
      }, onConflict: 'product_id,user_id');
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось сохранить отзыв');
    }
  }
}
