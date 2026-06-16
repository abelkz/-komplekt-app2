import 'package:flutter/material.dart';

/// Палитра КОМПЛЕКТ как ThemeExtension — токены 1:1 из HTML-прототипа.
/// Доступ из виджетов: `context.colors.orange`, `context.colors.line` и т.д.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.ink,
    required this.paper,
    required this.card,
    required this.line,
    required this.gray,
    required this.faint,
    required this.orange,
    required this.orangeSoft,
    required this.green,
    required this.greenSoft,
    required this.red,
    required this.redSoft,
    required this.field,
  });

  final Color ink; // основной текст
  final Color paper; // фон экрана
  final Color card; // карточки
  final Color line; // границы
  final Color gray; // вторичный текст
  final Color faint; // третичный текст / плейсхолдеры
  final Color orange; // акцент
  final Color orangeSoft;
  final Color green;
  final Color greenSoft;
  final Color red;
  final Color redSoft;
  final Color field; // поля ввода / чипы

  // Светлая тема (значения из :root прототипа)
  static const light = AppColors(
    ink: Color(0xFF17191A),
    paper: Color(0xFFF4F2EE),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFE8E5DF),
    gray: Color(0xFF73726D),
    faint: Color(0xFFA6A39C),
    orange: Color(0xFFE8490D),
    orangeSoft: Color(0xFFFDEAE0),
    green: Color(0xFF1C7A49),
    greenSoft: Color(0xFFE6F4EC),
    red: Color(0xFFBB4036),
    redSoft: Color(0xFFFBEAE8),
    field: Color(0xFFF4F2EE),
  );

  // Тёмная тема (html[data-theme="dark"])
  static const dark = AppColors(
    ink: Color(0xFFF3F1EC),
    paper: Color(0xFF141514),
    card: Color(0xFF1E201E),
    line: Color(0xFF2C2E2C),
    gray: Color(0xFF9A9893),
    faint: Color(0xFF6C6E6A),
    orange: Color(0xFFFF5A23),
    orangeSoft: Color(0xFF3A2118),
    green: Color(0xFF3FAE74),
    greenSoft: Color(0xFF15301F),
    red: Color(0xFFE0695E),
    redSoft: Color(0xFF341C19),
    field: Color(0xFF262826),
  );

  @override
  AppColors copyWith({
    Color? ink,
    Color? paper,
    Color? card,
    Color? line,
    Color? gray,
    Color? faint,
    Color? orange,
    Color? orangeSoft,
    Color? green,
    Color? greenSoft,
    Color? red,
    Color? redSoft,
    Color? field,
  }) {
    return AppColors(
      ink: ink ?? this.ink,
      paper: paper ?? this.paper,
      card: card ?? this.card,
      line: line ?? this.line,
      gray: gray ?? this.gray,
      faint: faint ?? this.faint,
      orange: orange ?? this.orange,
      orangeSoft: orangeSoft ?? this.orangeSoft,
      green: green ?? this.green,
      greenSoft: greenSoft ?? this.greenSoft,
      red: red ?? this.red,
      redSoft: redSoft ?? this.redSoft,
      field: field ?? this.field,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      ink: Color.lerp(ink, other.ink, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      card: Color.lerp(card, other.card, t)!,
      line: Color.lerp(line, other.line, t)!,
      gray: Color.lerp(gray, other.gray, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      orangeSoft: Color.lerp(orangeSoft, other.orangeSoft, t)!,
      green: Color.lerp(green, other.green, t)!,
      greenSoft: Color.lerp(greenSoft, other.greenSoft, t)!,
      red: Color.lerp(red, other.red, t)!,
      redSoft: Color.lerp(redSoft, other.redSoft, t)!,
      field: Color.lerp(field, other.field, t)!,
    );
  }
}

/// Сахар: `context.colors.orange`
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// Радиусы скругления из прототипа (--r-lg/md/sm).
class AppRadii {
  AppRadii._();
  static const double lg = 20;
  static const double md = 14;
  static const double sm = 11;
}
