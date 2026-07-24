import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../../product/domain/review.dart';

/// Отзывы о поставщике (таблица supplier_reviews).
class SupplierReviewsRepository {
  const SupplierReviewsRepository();

  Future<List<Review>> forSupplier(String supplierId) async {
    try {
      final rows = await supabase
          .from('supplier_reviews')
          .select('id,rating,text,created_at,user_id')
          .eq('supplier_id', supplierId)
          .order('created_at', ascending: false);
      return rows.map<Review>((m) => Review.fromMap(m)).toList();
    } catch (e) {
      if (e.toString().contains('supplier_reviews')) return const [];
      throw mapError(e, fallback: 'Не удалось загрузить отзывы');
    }
  }

  /// Один отзыв на поставщика от человека (upsert).
  Future<void> submit({
    required String supplierId,
    required int rating,
    String? text,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw const Failure('Нужно войти, чтобы оставить отзыв');
    try {
      await supabase.from('supplier_reviews').upsert({
        'supplier_id': int.tryParse(supplierId) ?? supplierId,
        'user_id': uid,
        'rating': rating,
        'text': text,
      }, onConflict: 'supplier_id,user_id');
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось сохранить отзыв');
    }
  }
}

final supplierReviewsRepositoryProvider =
    Provider((ref) => const SupplierReviewsRepository());

final supplierReviewsProvider =
    FutureProvider.family<List<Review>, String>((ref, supplierId) =>
        ref.read(supplierReviewsRepositoryProvider).forSupplier(supplierId));
