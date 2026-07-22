import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../domain/photo_match.dart';
import 'visual_search_providers.dart';

/// Экран 12 — поиск материалов по фотографии интерьера.
///
/// Фото уходит в серверную функцию, ИИ распознаёт на нём отделочные
/// материалы, а приложение превращает их в обычные запросы по каталогу.
class VisualSearchScreen extends ConsumerWidget {
  const VisualSearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(visualSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Поиск по фото'),
        actions: [
          if (state.valueOrNull?.result != null)
            TextButton(
              onPressed: () => ref.read(visualSearchProvider.notifier).reset(),
              child: const Text('Другое фото'),
            ),
        ],
      ),
      body: state.when(
        loading: () => const _Analyzing(),
        error: (e, _) => _Error(
          message: _msg(e),
          onRetry: () => _pick(context, ref, ImageSource.gallery),
        ),
        data: (data) => data.result == null
            ? _Empty(onPick: (src) => _pick(context, ref, src))
            : _Result(photo: data.photo, match: data.result!),
      ),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, ImageSource src) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Сжимаем прямо при выборе: на распознавание материалов такого
      // размера хватает с запасом, а трафик и стоимость запроса ниже.
      final file = await ImagePicker().pickImage(
        source: src,
        maxWidth: 1568,
        maxHeight: 1568,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final mime = file.path.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      await ref.read(visualSearchProvider.notifier).analyze(bytes, mediaType: mime);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  static String _msg(Object e) {
    final t = e.toString();
    return t.startsWith('Failure: ') ? t.substring(9) : 'Не удалось открыть фото';
  }
}

// ── Пустое состояние: приглашение выбрать фото ──
class _Empty extends StatelessWidget {
  const _Empty({required this.onPick});
  final void Function(ImageSource) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration:
                  BoxDecoration(color: c.orangeSoft, shape: BoxShape.circle),
              child: Icon(Icons.image_search, size: 44, color: c.orange),
            ),
          ),
          const SizedBox(height: 24),
          Text('Поиск по референсу интерьера',
              textAlign: TextAlign.center,
              style: AppTypography.unbounded(size: 18, color: c.ink)),
          const SizedBox(height: 10),
          Text(
            'Загрузите фото комнаты из Pinterest или с объекта — приложение '
            'распознает отделочные материалы и найдёт похожие у поставщиков.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.gray, height: 1.5),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: () => onPick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Выбрать из галереи'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.ink,
              side: BorderSide(color: c.line),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () => onPick(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Сфотографировать'),
          ),
        ],
      ),
    );
  }
}

// ── Ожидание ответа ──
class _Analyzing extends StatelessWidget {
  const _Analyzing();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(height: 18),
          Text('Разбираю фотографию…',
              style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 6),
          Text('Обычно занимает 5–15 секунд',
              style: TextStyle(fontSize: 13, color: c.gray)),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: c.faint),
            const SizedBox(height: 14),
            Text('Ошибка',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 5),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.gray)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Выбрать фото')),
          ],
        ),
      ),
    );
  }
}

// ── Результат разбора ──
class _Result extends StatelessWidget {
  const _Result({required this.photo, required this.match});
  final Uint8List? photo;
  final PhotoMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Image.memory(photo!,
                height: 200, width: double.infinity, fit: BoxFit.cover),
          ),
        const SizedBox(height: 16),
        if (match.room.isNotEmpty || match.style.isNotEmpty)
          Text(
            [match.room, match.style].where((s) => s.isNotEmpty).join(' · '),
            style: AppTypography.unbounded(size: 16, color: c.ink),
          ),
        const SizedBox(height: 4),
        Text('НАЙДЕНО МАТЕРИАЛОВ: ${match.materials.length}',
            style: AppTypography.sectionLabel(color: c.gray)),
        const SizedBox(height: 14),
        for (final m in match.materials) _MaterialRow(material: m),
        const SizedBox(height: 12),
        Text(
          'Материалы определены по фотографии — сверьтесь с карточкой товара '
          'перед заказом.',
          style: TextStyle(fontSize: 12, color: c.faint, height: 1.4),
        ),
      ],
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({required this.material});
  final PhotoMaterial material;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.push('${Routes.search}?q=${Uri.encodeQueryComponent(material.query)}'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            children: [
              // образец цвета материала
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: material.color ?? c.field,
                  border: Border.all(color: c.line),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(material.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (material.where.isNotEmpty) material.where,
                        'искать: ${material.query}',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: c.gray),
                    ),
                  ],
                ),
              ),
              Icon(Icons.search, size: 18, color: c.accent),
            ],
          ),
        ),
      ),
    );
  }
}
