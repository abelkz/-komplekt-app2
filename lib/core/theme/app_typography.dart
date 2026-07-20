import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Типографика дизайна «Спецификация»:
///  • Golos Text — основной текст (body, подписи, кнопки), хорошая кириллица
///  • Unbounded — заголовки, цены и крупные акценты
///  • JetBrains Mono — служебные подписи: артикулы, даты, индексы, метки
///    разделов. Моноширинный шрифт даёт ощущение технического документа.
class AppTypography {
  AppTypography._();

  /// Заголовок в стиле бренда (Unbounded, плотный, с отрицательным трекингом).
  static TextStyle unbounded({
    double size = 21,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = -0.6,
  }) {
    return GoogleFonts.unbounded(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: 1.1,
    );
  }

  /// Служебная моноширинная подпись: артикул, дата, «01», «▼ 6,0%».
  static TextStyle mono({
    double size = 10.5,
    FontWeight weight = FontWeight.w600,
    Color? color,
    double letterSpacing = 0.5,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: 1.3,
    );
  }

  /// Метка раздела: «КАТЕГОРИИ», «ШКАЛА ЦЕН» — моно, вразрядку, капсом.
  /// Текст подавайте уже в верхнем регистре.
  static TextStyle sectionLabel({Color? color}) => GoogleFonts.jetBrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 1.5,
        height: 1.2,
      );

  /// Сборка TextTheme: база — Golos Text, дисплейные стили — Unbounded.
  static TextTheme textTheme(Color onColor) {
    final base = GoogleFonts.golosTextTextTheme();
    return base.apply(bodyColor: onColor, displayColor: onColor).copyWith(
          displayLarge: GoogleFonts.unbounded(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
            height: 1.05,
            color: onColor,
          ),
          displayMedium: GoogleFonts.unbounded(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
            height: 1.05,
            color: onColor,
          ),
          displaySmall: GoogleFonts.unbounded(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: onColor,
          ),
          headlineSmall: GoogleFonts.unbounded(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: onColor,
          ),
          titleMedium: GoogleFonts.golosText(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            height: 1.25,
            color: onColor,
          ),
          bodyMedium: GoogleFonts.golosText(fontSize: 14, color: onColor),
          bodySmall: GoogleFonts.golosText(fontSize: 12.5, color: onColor),
          labelLarge: GoogleFonts.golosText(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: onColor,
          ),
          labelSmall: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: onColor,
          ),
        );
  }
}
