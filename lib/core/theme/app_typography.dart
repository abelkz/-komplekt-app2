import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Типографика из прототипа:
///  • Manrope — основной текст (body, подписи, кнопки)
///  • Unbounded — заголовки и крупные акценты (h1, итог)
class AppTypography {
  AppTypography._();

  /// Заголовок в стиле бренда (Unbounded, плотный).
  static TextStyle unbounded({
    double size = 21,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = -0.4,
  }) {
    return GoogleFonts.unbounded(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: 1.1,
    );
  }

  /// Сборка TextTheme: база — Manrope, дисплейные стили — Unbounded.
  static TextTheme textTheme(Color onColor) {
    final base = GoogleFonts.manropeTextTheme();
    return base
        .apply(bodyColor: onColor, displayColor: onColor)
        .copyWith(
          displaySmall: GoogleFonts.unbounded(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: onColor,
          ),
          headlineSmall: GoogleFonts.unbounded(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: onColor,
          ),
          titleMedium: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: onColor,
          ),
          bodyMedium: GoogleFonts.manrope(fontSize: 14, color: onColor),
          bodySmall: GoogleFonts.manrope(fontSize: 12, color: onColor),
          labelLarge: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: onColor,
          ),
        );
  }
}
