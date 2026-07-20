import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/review.dart';
import '../product_providers.dart';

/// Блок отзывов на карточке товара + форма добавления.
class ReviewsSection extends ConsumerWidget {
  const ReviewsSection({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final reviews = ref.watch(reviewsProvider(productId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('ОТЗЫВЫ',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: c.faint)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _openForm(context, ref),
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              label: const Text('Оставить'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        reviews.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) =>
              Text('Не удалось загрузить отзывы', style: TextStyle(color: c.gray)),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Пока нет отзывов — будьте первым.',
                      style: TextStyle(color: c.gray, fontSize: 13)),
                )
              : Column(
                  children: [for (final r in list) _ReviewTile(review: r)],
                ),
        ),
      ],
    );
  }

  void _openForm(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReviewForm(productId: productId),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final Review review;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(review.authorName,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              _Stars(review.rating),
            ],
          ),
          if (review.text != null && review.text!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(review.text!,
                style: TextStyle(fontSize: 13, color: c.gray, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars(this.rating);
  final int rating;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          Icon(i <= rating ? Icons.star_rounded : Icons.star_border,
              size: 16, color: c.orange),
      ],
    );
  }
}

class _ReviewForm extends ConsumerStatefulWidget {
  const _ReviewForm({required this.productId});
  final String productId;
  @override
  ConsumerState<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends ConsumerState<_ReviewForm> {
  int _rating = 5;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(reviewControllerProvider).isLoading;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 22,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ваш отзыв',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            children: [
              for (int i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                    i <= _rating
                        ? Icons.star_rounded
                        : Icons.star_border,
                    color: context.colors.orange,
                    size: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            maxLines: 3,
            decoration:
                const InputDecoration(hintText: 'Поделитесь впечатлением…'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: loading ? null : _submit,
              child: loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.brandInk))
                  : const Text('Отправить'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final ok = await ref.read(reviewControllerProvider.notifier).submit(
          productId: widget.productId,
          rating: _rating,
          text: _text.text.trim(),
        );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Спасибо за отзыв!')));
    } else {
      final err = ref.read(reviewControllerProvider).error;
      final msg = err.toString().startsWith('Failure: ')
          ? err.toString().substring(9)
          : 'Не удалось отправить';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
