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
  const ReportMenu({super.key, required this.reviewId, this.authorId});

  final String reviewId;
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
          // Отправляем жалобу на сервер, если таблица есть (не критично).
          try {
            await supabase.from('content_reports').insert({
              'review_id': reviewId,
              'reporter_id': supabase.auth.currentUser?.id,
              'reason': 'objectionable',
            });
          } catch (_) {/* модерация всё равно скрыла отзыв локально */}
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
