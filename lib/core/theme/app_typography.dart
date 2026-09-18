import 'dart:ui' show FontFeature;

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

  /// Метка раздела: «ХАРАКТЕРИСТИКИ», «ЦЕНЫ ПОСТАВЩИКОВ» — Inter, вразрядку,
  /// капсом. Текст подавайте уже в верхнем регистре.
  ///
  /// Трекинг 1.4 — из макета (`mono-label-spec`), это единственная метка
  /// такого рода в системе, и она держит «чертёжный» характер интерфейса.
  static TextStyle sectionLabel({Color? color}) => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 1.4,
        height: 14 / 11,
      );

  // ──────────────────────────────────────────────────────────────────────
  // Токены из макета (design/stitch/Стич/design_system/DESIGN.md).
  //
  // Именованные стили вместо разрозненных чисел по виджетам: правка размера
  // делается здесь, а не поиском по файлам. Старые `unbounded`/`mono`/
  // `sectionLabel` оставлены — на них завязано полсотни виджетов.
  // ──────────────────────────────────────────────────────────────────────

  /// Manrope 30/36 — самый крупный заголовок (итог сметы, название экрана).
  static TextStyle headlineLg({Color? color}) => GoogleFonts.manrope(
        fontSize: 30,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: -0.5,
        height: 36 / 30,
      );

  /// Manrope 22/28 — название товара на карточке, заголовок раздела.
  static TextStyle headlineMd({Color? color}) => GoogleFonts.manrope(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: -0.2,
        height: 28 / 22,
      );

  /// Manrope 18/24 — подзаголовок.
  static TextStyle headlineSm({Color? color}) => GoogleFonts.manrope(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: color,
        height: 24 / 18,
      );

  /// Manrope 15/20 — название товара в сетке каталога, заголовок строки.
  static TextStyle titleMd({Color? color}) => GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: color,
        height: 20 / 15,
      );

  /// Inter 15/22 — основной текст.
  static TextStyle bodyLg({Color? color}) => GoogleFonts.inter(
        fontSize: 15,
        color: color,
        letterSpacing: -0.1,
        height: 22 / 15,
      );

  /// Inter 13/18 — вторичный текст, имя поставщика в таблице.
  static TextStyle bodyMd({Color? color}) => GoogleFonts.inter(
        fontSize: 13,
        color: color,
        height: 18 / 13,
      );

  /// Inter 12/16 — приглушённые подписи, сроки доставки.
  static TextStyle bodySm({Color? color}) => GoogleFonts.inter(
        fontSize: 12,
        color: color,
        height: 16 / 12,
      );

  /// JetBrains Mono 20/24 — крупная цена («от 4 290 ₸», итог сметы).
  ///
  /// `tnum` обязателен: без табличных цифр колонка цен в сравнении
  /// поставщиков перестаёт выравниваться, а ради неё всё и затевалось.
  static TextStyle priceLg({Color? color}) => GoogleFonts.jetBrainsMono(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: -0.5,
        height: 24 / 20,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// JetBrains Mono 15/20 — цена в строке таблицы.
  static TextStyle priceMd({Color? color}) => GoogleFonts.jetBrainsMono(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: -0.2,
        height: 20 / 15,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// JetBrains Mono 12/16 — числа и артикулы: количество, размеры, SKU.
  static TextStyle data({Color? color}) => GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: color,
        height: 16 / 12,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Сборка TextTheme: база — Inter, дисплейные стили — Manrope.
  static TextTheme textTheme(Color onColor) {
    final base = GoogleFonts.interTextTheme();
    return base.apply(bodyColor: onColor, displayColor: onColor).copyWith(
          // Значения — из макета. Начертания стали легче (w600 вместо w800):
          // в «чертёжной» системе иерархию держат размер и трекинг, а не
          // жир — от него плотная кириллица выглядит грубо.
          displayLarge: headlineLg(color: onColor),
          displayMedium: headlineMd(color: onColor),
          displaySmall: headlineSm(color: onColor),
          headlineSmall: headlineSm(color: onColor),
          titleMedium: titleMd(color: onColor),
          bodyLarge: bodyLg(color: onColor),
          bodyMedium: bodyMd(color: onColor),
          bodySmall: bodySm(color: onColor),
          labelLarge: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: onColor,
          ),
          labelSmall: sectionLabel(color: onColor),
        );
  }
}
