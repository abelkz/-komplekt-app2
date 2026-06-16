import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Поиск по фото/референсу интерьера — заглушка на MVP.
/// Кнопка и экран есть, логика подбора по изображению добавится позже.
class VisualSearchScreen extends StatelessWidget {
  const VisualSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Поиск по фото')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                    color: c.orangeSoft, shape: BoxShape.circle),
                child: Icon(Icons.image_search,
                    size: 44, color: c.orange),
              ),
              const SizedBox(height: 22),
              Text('Поиск по референсу интерьера',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.ink)),
              const SizedBox(height: 10),
              Text(
                'Загрузите фото комнаты из Pinterest или с объекта — '
                'и приложение подберёт похожие материалы у поставщиков. '
                'Функция появится в одном из ближайших обновлений.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.gray, height: 1.5),
              ),
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Скоро: подбор материалов по фото')),
                ),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Загрузить фото'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
