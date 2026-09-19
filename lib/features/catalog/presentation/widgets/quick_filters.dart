import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../catalog_providers.dart';
import 'filters_sheet.dart';

/// Полоса быстрых фильтров над списком товаров: наличие, марка, сортировка
/// и вход в полный лист фильтров.
///
/// То же самое есть в листе фильтров, но лист — это три касания и закрытый
/// список. Сортировка по цене — главное, ради чего сюда заходят, и прятать
/// её за кнопкой неправильно. Состояние общее с листом: то, что выбрано
/// чипом, там подсвечено, и наоборот.
class QuickFilters extends ConsumerWidget {
  const QuickFilters({super.key, this.brands = const []});

  /// Марки из нефильтрованного набора. Пустой список — чипы марок не нужны.
  final List<String> brands;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final f = ref.watch(filtersProvider);
    final notifier = ref.read(filtersProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            FilterChipBox(
              label: 'В наличии',
              selected: f.inStock,
              onTap: () => notifier.apply(f.copyWith(inStock: !f.inStock)),
            ),
            const SizedBox(width: 8),
            for (final s in SortBy.values) ...[
              FilterChipBox(
                label: s.label,
                selected: f.sort == s,
                onTap: () => notifier.apply(f.copyWith(sort: s)),
              ),
              const SizedBox(width: 8),
            ],
            // Потолок цены задаётся в листе — чип только показывает, что он
            // стоит, и снимает его одним касанием.
            if (f.maxPrice != null) ...[
              FilterChipBox(
                label: 'До ${Formatters.price(f.maxPrice!)}',
                selected: true,
                onTap: () => notifier.apply(f.copyWith(clearMaxPrice: true)),
              ),
              const SizedBox(width: 8),
            ],
            if (f.city != 'Все города') ...[
              FilterChipBox(
                label: f.city,
                selected: true,
                onTap: () => notifier.apply(f.copyWith(city: 'Все города')),
              ),
              const SizedBox(width: 8),
            ],
            for (final b in brands) ...[
              FilterChipBox(
                label: b,
                selected: f.brand == b,
                onTap: () => notifier.apply(
                  f.brand == b
                      ? f.copyWith(clearBrand: true)
                      : f.copyWith(brand: b),
                ),
              ),
              const SizedBox(width: 8),
            ],
            FilterChipBox(
              label: 'Все фильтры',
              selected: false,
              icon: Icons.tune_rounded,
              onTap: () => showFiltersSheet(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

/// Чип-фильтр: прямоугольный, с тёплой линейкой и жёлтой заливкой
/// у выбранного — как остальные управляющие элементы приложения.
class FilterChipBox extends StatelessWidget {
  const FilterChipBox({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? AppColors.brandInk : c.gray;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.field,
          border: Border.all(color: selected ? c.accent : c.line),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «1 товар», «2 товара», «128 товаров».
///
/// Счётчик в шапке читают глазами, и «128 товара» там сразу бросается
/// в глаза как ошибка.
String productsPlural(int n) {
  final rest100 = n % 100;
  if (rest100 >= 11 && rest100 <= 14) return 'товаров';
  switch (n % 10) {
    case 1:
      return 'товар';
    case 2:
    case 3:
    case 4:
      return 'товара';
    default:
      return 'товаров';
  }
}
