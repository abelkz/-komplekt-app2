import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/supabase_client.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';

/// Счётчик, который «дёргается» при жалобе/скрытии, чтобы списки отзывов
/// перечитали локальное хранилище и убрали скрытое сразу.
final moderationTickProvider = StateProvider<int>((ref) => 0);

/// Меню модерации отзыва (пользовательский контент): «Пожаловаться» и
/// «Скрыть отзывы пользователя». Требование App Store 1.2 — дать людям
/// способ пожаловаться на контент и заблокировать автора.
class ReportMenu extends ConsumerWidget {
  const ReportMenu({
    super.key,
    required this.reviewId,
    required this.target,
    this.authorId,
  });

  final String reviewId;

  /// Откуда отзыв: `product_review` или `supplier_review`. Без этого по одному
  /// `reviewId` не понять, в какой таблице искать — у отзывов о товарах id
  /// типа uuid, у отзывов о поставщиках bigint (см. миграцию 0025).
  final String target;

  final String? authorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: 18, color: c.faint),
      tooltip: 'Пожаловаться',
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'report', child: Text('Пожаловаться')),
        if (authorId != null)
          const PopupMenuItem(
              value: 'block', child: Text('Скрыть отзывы пользователя')),
      ],
      onSelected: (v) async {
        final store = ref.read(localStoreProvider);
        final messenger = ScaffoldMessenger.of(context);

        if (v == 'report') {
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('Пожаловаться на отзыв?'),
              content: const Text(
                  'Отзыв будет скрыт у вас, а жалоба отправлена на проверку. '
                  'Мы удаляем оскорбительный и незаконный контент.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d, false),
                    child: const Text('Отмена')),
                FilledButton(
                    onPressed: () => Navigator.pop(d, true),
                    child: const Text('Пожаловаться')),
              ],
            ),
          );
          if (ok != true) return;
          await store.hideReview(reviewId);
          // Жалоба уходит администратору в content_reports (миграция 0025).
          // Сбой не показываем пользователю: отзыв у него уже скрыт, а
          // повторное «не отправилось» ничего не даст. Но и не глотаем молча —
          // пишем в лог, иначе пропажа жалоб опять останется незамеченной.
          try {
            await supabase.from('content_reports').insert({
              'target': target,
              'review_id': reviewId,
              'reporter_id': supabase.auth.currentUser?.id,
              'reason': 'objectionable',
            });
          } catch (e) {
            debugPrint('Жалоба не сохранилась ($target $reviewId): $e');
          }
          ref.read(moderationTickProvider.notifier).state++;
          messenger.showSnackBar(
              const SnackBar(content: Text('Жалоба отправлена, отзыв скрыт')));
        } else if (v == 'block' && authorId != null) {
          await store.blockUser(authorId!);
          ref.read(moderationTickProvider.notifier).state++;
          messenger.showSnackBar(const SnackBar(
              content: Text('Отзывы этого пользователя скрыты')));
        }
      },
    );
  }
}
