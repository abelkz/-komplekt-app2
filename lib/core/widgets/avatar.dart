import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Аватарка человека или логотип компании.
///
/// Один виджет на оба случая: правила одинаковые — есть снимок, показываем
/// его; нет — показываем монограмму из имени. Разводить две почти одинаковые
/// реализации значит однажды поправить одну и забыть вторую.
///
/// Форма у обоих одна — прямоугольник со скруглением, без круга. Это решение
/// в проекте уже принято для монограммы в профиле: круглые аватары — язык
/// соцсетей, здесь учётная запись и компания. Человека от компании отличает
/// цвет монограммы, а не форма.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.url,
    this.size = 44,
    this.company = false,
  });

  /// Имя или название — из него берётся монограмма.
  final String name;

  /// Публичная ссылка на файл. null или пусто — будет монограмма.
  final String? url;

  final double size;

  /// Компания, а не человек: монограмма жёлтая вместо серой.
  final bool company;

  /// Одна буква, не две. Двухбуквенные монограммы читаются как аббревиатура
  /// компании, а у «Ивана» и «Иванова» они одинаковые — толку от второй буквы
  /// нет, а места она занимает вдвое больше.
  String get _letter {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return t.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = size * 0.28;
    final link = url?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.field,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: (link == null || link.isEmpty)
            ? _Monogram(letter: _letter, size: size, company: company)
            : CachedNetworkImage(
                imageUrl: link,
                fit: BoxFit.cover,
                // Пока грузится — та же монограмма, а не серый прямоугольник:
                // иначе список подпрыгивает и мигает при прокрутке.
                placeholder: (_, __) =>
                    _Monogram(letter: _letter, size: size, company: company),
                // Битая ссылка — тоже монограмма. Значок «картинка не
                // загрузилась» здесь ничего не сообщает человеку: починить
                // он это всё равно не может.
                errorWidget: (_, __, ___) =>
                    _Monogram(letter: _letter, size: size, company: company),
              ),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({
    required this.letter,
    required this.size,
    required this.company,
  });

  final String letter;
  final double size;
  final bool company;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: company ? c.accent : c.gray,
        ),
      ),
    );
  }
}
