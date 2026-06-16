import 'package:flutter/material.dart';

/// Сопоставление slug категории → иконка Material (близко к SVG прототипа).
class CategoryIcons {
  CategoryIcons._();

  static const Map<String, IconData> _map = {
    'tile': Icons.grid_view_rounded, // Керамогранит
    'laminate': Icons.view_day_rounded, // Ламинат
    'plumbing': Icons.water_drop_outlined, // Сантехника
    'light': Icons.lightbulb_outline, // Освещение
    'electric': Icons.bolt, // Электрика
    'doors': Icons.door_front_door_outlined, // Двери
    'paint': Icons.format_paint_outlined, // Краска
    'furniture': Icons.chair_outlined, // Мебель
    'decor': Icons.diamond_outlined, // Декор
    'wallpaper': Icons.wallpaper, // Обои
  };

  static IconData of(String? slug) =>
      _map[slug] ?? Icons.category_outlined;
}
