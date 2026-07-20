import 'package:flutter/material.dart';

/// Палитра КОМПЛЕКТ как ThemeExtension — токены дизайна «Спецификация»:
/// тушь на кости + сигнальный хром-жёлтый маркер.
/// Доступ из виджетов: `context.colors.accent`, `context.colors.line` и т.д.
///
/// Имена полей сохранены с прошлой версии темы, чтобы не переписывать
/// полсотни виджетов. Важно: поле [orange] теперь хранит хром-жёлтый акцент —
/// для нового кода используйте понятный псевдоним [accent].
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

  final Color ink; // основной текст / «тушь»
  final Color paper; // фон экрана / «кость»
  final Color card; // поверхности
  final Color line; // тонкие линейки
  final Color gray; // вторичный текст
  final Color faint; // третичный текст / плейсхолдеры
  final Color orange; // акцент (хром-жёлтый) — см. [accent]
  final Color orangeSoft; // мягкая подложка акцента
  final Color green;
  final Color greenSoft;
  final Color red;
  final Color redSoft;
  final Color field; // поля ввода / чипы

  /// Хром-жёлтый акцент — понятное имя для [orange].
  Color get accent => orange;

  /// Мягкая жёлтая подложка — понятное имя для [orangeSoft].
  Color get accentSoft => orangeSoft;

  /// Константы бренда, не зависящие от темы: на жёлтом текст всегда тушью,
  /// а «рулетка» навигации всегда тёмная.
  static const brandInk = Color(0xFF161410);
  static const brandBone = Color(0xFFEAE5DA);
  static const brandYellow = Color(0xFFF2B800);

  // Светлая тема: тушь на кости
  static const light = AppColors(
    ink: Color(0xFF161410),
    paper: Color(0xFFEAE5DA),
    card: Color(0xFFF1ECE3),
    line: Color(0xFFB5B1A8),
    gray: Color(0xFF75726B),
    faint: Color(0xFF8B877F),
    orange: brandYellow,
    orangeSoft: Color(0xFFF6E7AE),
    green: Color(0xFF0D7A3F),
    greenSoft: Color(0xFFD9E8DE),
    red: Color(0xFFB3400E),
    redSoft: Color(0xFFF2DCD2),
    field: Color(0xFFF2EFE7),
  );

  // Тёмная тема: кость на туши
  static const dark = AppColors(
    ink: Color(0xFFEAE5DA),
    paper: Color(0xFF161410),
    card: Color(0xFF1E1B16),
    line: Color(0xFF4B4842),
    gray: Color(0xFF8B877F),
    faint: Color(0xFF75726B),
    orange: brandYellow,
    orangeSoft: Color(0xFF3A2E10),
    green: Color(0xFF0FA45A),
    greenSoft: Color(0xFF13301E),
    red: Color(0xFFD05A28),
    redSoft: Color(0xFF34190F),
    field: Color(0xFF221F19),
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

/// Сахар: `context.colors.accent`
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// Скругления. В «Спецификации» углы острые — приложение выглядит
/// как типографский документ, а не как набор мягких карточек.
class AppRadii {
  AppRadii._();
  static const double lg = 0;
  static const double md = 0;
  static const double sm = 0;
}
