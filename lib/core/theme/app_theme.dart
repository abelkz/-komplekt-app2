import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Сборка светлой и тёмной темы (Material 3) в дизайне «Спецификация».
/// Ключевые принципы стиля: острые углы, тонкие линейки вместо теней,
/// жёлтый маркер как единственный акцент, моноширинные служебные подписи.
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
      // на жёлтом текст всегда тушью — в обеих темах
      onPrimary: AppColors.brandInk,
      surface: c.paper,
      onSurface: c.ink,
      error: c.red,
    );

    // Прямоугольник без скруглений — базовая форма всего интерфейса.
    const sharp = RoundedRectangleBorder(borderRadius: BorderRadius.zero);

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
        titleTextStyle: AppTypography.unbounded(size: 17, color: c.ink),
        // тонкая линейка под шапкой вместо тени
        shape: Border(bottom: BorderSide(color: c.ink, width: 1.5)),
      ),

      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: sharp.copyWith(side: BorderSide(color: c.line)),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.field,
        hintStyle: TextStyle(color: c.faint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: c.ink, width: 1.5),
        ),
      ),

      // Тёмная кнопка-«штамп»: тушь на кости.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.ink,
          foregroundColor: c.paper,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          shape: sharp,
        ),
      ),

      // Главное действие — жёлтый маркер с текстом тушью.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: AppColors.brandInk,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          shape: sharp,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          side: BorderSide(color: c.line),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: sharp,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.ink, shape: sharp),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.brandInk,
        selectedItemColor: AppColors.brandYellow,
        unselectedItemColor: AppColors.brandBone.withValues(alpha: 0.55),
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 0,
      ),

      // Чип-«бирка»: прямоугольная, с тонкой рамкой.
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        side: BorderSide(color: c.line),
        labelStyle: AppTypography.mono(size: 11, color: c.ink),
        shape: sharp,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),

      // Шторка снизу — как лист документа с жирной линейкой сверху.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.paper,
        elevation: 0,
        shape: Border(top: BorderSide(color: c.ink, width: 2)),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.brandInk,
        contentTextStyle: AppTypography.mono(
          size: 11.5,
          color: AppColors.brandBone,
        ),
        behavior: SnackBarBehavior.floating,
        shape: sharp,
      ),

      dialogTheme: DialogThemeData(backgroundColor: c.paper, shape: sharp),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.line,
      ),
    );
  }
}
