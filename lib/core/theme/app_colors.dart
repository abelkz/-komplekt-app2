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
  // На жёлтом всегда тёмно-коричневый текст (on-primary из «Industrial Noir»).
  static const brandInk = Color(0xFF241A00);
  static const brandBone = Color(0xFFE3E2E2);
  static const brandYellow = Color(0xFFFABD00);

  // Светлая тема: тёплая «кость» + золото, скруглённые поверхности.
  static const light = AppColors(
    ink: Color(0xFF1B1B1A),
    paper: Color(0xFFF7F4EF),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFE3DED3),
    gray: Color(0xFF6B6558),
    faint: Color(0xFF8F897C),
    orange: Color(0xFFE0A500),
    orangeSoft: Color(0xFFFBEFC7),
    green: Color(0xFF12855A),
    greenSoft: Color(0xFFDCEFE4),
    red: Color(0xFFB3261E),
    redSoft: Color(0xFFF7DAD7),
    field: Color(0xFFF1EDE5),
  );

  // Тёмная тема — «Industrial Noir»: глубокий графит, тёплый золотой акцент.
  static const dark = AppColors(
    ink: Color(0xFFE3E2E2), // on-surface
    paper: Color(0xFF121414), // background
    card: Color(0xFF1E2020), // surface-container
    line: Color(0xFF4F4632), // outline-variant (тёплая рамка)
    gray: Color(0xFFD4C5AB), // on-surface-variant (тёплый вторичный текст)
    faint: Color(0xFF9C8F78), // outline (приглушённый)
    orange: brandYellow, // золотой акцент
    orangeSoft: Color(0xFF3A2E10),
    green: Color(0xFF35C88A),
    greenSoft: Color(0xFF14331F),
    red: Color(0xFFFFB4AB), // светлый лосось (рост цены / скидка)
    redSoft: Color(0xFF4A1512),
    field: Color(0xFF1E2020),
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

/// Скругления «Industrial Noir»: мягкие премиальные карточки.
/// lg — крупные контейнеры и шторки, md — карточки, sm — кнопки/поля/чипы.
class AppRadii {
  AppRadii._();
  static const double lg = 16;
  static const double md = 12;
  static const double sm = 8;
}
