import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Сборка светлой и тёмной темы (Material 3) в дизайне «Industrial Noir».
/// Принципы: глубокие графитовые поверхности слоями (без тяжёлых теней),
/// тёплый золотой акцент только для действий и важного, мягкие скругления,
/// тонкие тёплые линейки-рамки.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
    ).copyWith(
      primary: c.accent,
      // на жёлтом текст всегда тёмно-коричневый — в обеих темах
      onPrimary: AppColors.brandInk,
      surface: c.paper,
      onSurface: c.ink,
      surfaceContainerHighest: c.card,
      outline: c.line,
      error: c.red,
    );

    RoundedRectangleBorder rounded(double r, {BorderSide? side}) =>
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r),
          side: side ?? BorderSide.none,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.paper,
      canvasColor: c.paper,
      textTheme: AppTypography.textTheme(c.ink),
      extensions: [c],
      dividerColor: c.line,
      splashFactory: InkRipple.splashFactory,

      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),

      appBarTheme: AppBarTheme(
        backgroundColor: c.paper,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.unbounded(size: 18, color: c.ink),
        // тонкая тёплая линейка под шапкой вместо тени
        shape: Border(bottom: BorderSide(color: c.line, width: 1)),
      ),

      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: rounded(AppRadii.lg, side: BorderSide(color: c.line)),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.field,
        hintStyle: TextStyle(color: c.faint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),

      // Заметная нейтральная кнопка (второстепенное действие): поверхность
      // с тонкой рамкой — «secondary» из макета.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.card,
          foregroundColor: c.ink,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          shape: rounded(AppRadii.sm, side: BorderSide(color: c.line)),
        ),
      ),

      // Главное действие — золотая пилюля с тёмным текстом.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: AppColors.brandInk,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          shape: rounded(AppRadii.sm),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          side: BorderSide(color: c.line),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: rounded(AppRadii.sm),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          shape: rounded(AppRadii.sm),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.card,
        selectedItemColor: c.accent,
        unselectedItemColor: c.faint,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 0,
      ),

      // Чип-пилюля с мягкой подложкой.
      chipTheme: ChipThemeData(
        backgroundColor: c.field,
        side: BorderSide(color: c.line),
        labelStyle: AppTypography.sectionLabel(color: c.ink)
            .copyWith(letterSpacing: 0.2),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      ),

      // Шторка снизу — приподнятая поверхность со скруглённым верхом.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.lg),
          ),
          side: BorderSide(color: c.line),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.card,
        contentTextStyle: AppTypography.mono(
          size: 12,
          color: c.ink,
        ),
        behavior: SnackBarBehavior.floating,
        shape: rounded(AppRadii.md, side: BorderSide(color: c.line)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        shape: rounded(AppRadii.lg, side: BorderSide(color: c.line)),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.line,
      ),
    );
  }
}
