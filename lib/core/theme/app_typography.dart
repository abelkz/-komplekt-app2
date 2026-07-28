import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Типографика «Industrial Noir»:
///  • Manrope — заголовки, цены и крупные акценты (геометричный гротеск,
///    полная кириллица; близок к Hanken Grotesk из макета, но читается по-русски)
///  • Inter — основной текст, подписи, кнопки (отличная кириллица, чёткий на
///    мелких размерах)
///  • JetBrains Mono — служебные подписи: артикулы, даты, индексы, метки
///    разделов — техничный «документальный» акцент.
class AppTypography {
  AppTypography._();

  /// Заголовок в стиле бренда (Manrope, плотный, с отрицательным трекингом).
  /// Имя метода сохранено для совместимости с прежними вызовами.
  static TextStyle unbounded({
    double size = 21,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = -0.5,
  }) {
    return GoogleFonts.manrope(
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

  /// Метка раздела: «КАТЕГОРИИ», «ШКАЛА ЦЕН» — Inter, вразрядку, капсом.
  /// Текст подавайте уже в верхнем регистре.
  static TextStyle sectionLabel({Color? color}) => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 1.2,
        height: 1.2,
      );

  /// Сборка TextTheme: база — Inter, дисплейные стили — Manrope.
  static TextTheme textTheme(Color onColor) {
    final base = GoogleFonts.interTextTheme();
    return base.apply(bodyColor: onColor, displayColor: onColor).copyWith(
          displayLarge: GoogleFonts.manrope(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            height: 1.05,
            color: onColor,
          ),
          displayMedium: GoogleFonts.manrope(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.06,
            color: onColor,
          ),
          displaySmall: GoogleFonts.manrope(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: onColor,
          ),
          headlineSmall: GoogleFonts.manrope(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: onColor,
          ),
          titleMedium: GoogleFonts.inter(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            height: 1.25,
            color: onColor,
          ),
          bodyMedium: GoogleFonts.inter(fontSize: 14, color: onColor),
          bodySmall: GoogleFonts.inter(fontSize: 12.5, color: onColor),
          labelLarge: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: onColor,
          ),
          labelSmall: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: onColor,
          ),
        );
  }
}
