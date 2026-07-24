import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../product/domain/review.dart';
import '../../data/supplier_reviews_repository.dart';

/// Отзывы о поставщике на витрине + форма «оставить».
class SupplierReviewsSection extends ConsumerWidget {
  const SupplierReviewsSection({super.key, required this.supplierId});
  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final reviews = ref.watch(supplierReviewsProvider(supplierId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('ОТЗЫВЫ О ПРОДАВЦЕ',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: c.faint)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => _Form(supplierId: supplierId),
              ),
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
              : Column(children: [for (final r in list) _Tile(review: r)]),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.review});
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

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.supplierId});
  final String supplierId;
  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  int _rating = 5;
  bool _busy = false;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(supplierReviewsRepositoryProvider).submit(
            supplierId: widget.supplierId,
            rating: _rating,
            text: _text.text.trim(),
          );
      ref.invalidate(supplierReviewsProvider(widget.supplierId));
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Спасибо за отзыв!')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final t = e.toString();
      messenger.showSnackBar(SnackBar(
          content:
              Text(t.startsWith('Failure: ') ? t.substring(9) : 'Не удалось')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
          const Text('Отзыв о продавце',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            children: [
              for (int i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                    i <= _rating ? Icons.star_rounded : Icons.star_border,
                    color: c.orange,
                    size: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: 'Как прошла сделка? Цены, наличие, доставка…'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
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
}
