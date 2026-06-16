import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../catalog/domain/product.dart';
import '../domain/review.dart';

/// Карточка товара по id.
final productProvider =
    FutureProvider.family<Product, String>((ref, id) async {
  return ref.watch(catalogRepositoryProvider).byId(id);
});

/// Отзывы товара.
final reviewsProvider =
    FutureProvider.family<List<Review>, String>((ref, productId) async {
  return ref.watch(reviewsRepositoryProvider).forProduct(productId);
});

/// Отправка отзыва.
class ReviewController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> submit({
    required String productId,
    required int rating,
    String? text,
  }) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(reviewsRepositoryProvider)
          .submit(productId: productId, rating: rating, text: text);
      ref.invalidate(reviewsProvider(productId));
      ref.invalidate(productProvider(productId));
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final reviewControllerProvider =
    AsyncNotifierProvider<ReviewController, void>(ReviewController.new);
