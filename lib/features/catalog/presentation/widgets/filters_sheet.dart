import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../catalog_providers.dart';

/// Нижний лист фильтров: город · только в наличии · сортировка.
Future<void> showFiltersSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _FiltersSheet(),
  );
}

class _FiltersSheet extends ConsumerStatefulWidget {
  const _FiltersSheet();
  @override
  ConsumerState<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<_FiltersSheet> {
  late CatalogFilters _draft = ref.read(filtersProvider);

  static const _cities = ['Все города', 'Астана', 'Алматы', 'Шымкент'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 22,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Фильтры',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 18),

          _label('Город'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final city in _cities)
                _Pill(
                  label: city,
                  selected: _draft.city == city,
                  onTap: () => setState(() => _draft = _draft.copyWith(city: city)),
                ),
            ],
          ),
          const SizedBox(height: 18),

          _label('Сортировка'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in SortBy.values)
                _Pill(
                  label: s.label,
                  selected: _draft.sort == s,
                  onTap: () => setState(() => _draft = _draft.copyWith(sort: s)),
                ),
            ],
          ),
          const SizedBox(height: 18),

          InkWell(
            borderRadius: BorderRadius.circular(AppRadii.md),
            onTap: () =>
                setState(() => _draft = _draft.copyWith(inStock: !_draft.inStock)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              decoration: BoxDecoration(
                color: c.field,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Row(
                children: [
                  const Text('Только в наличии',
                      style: TextStyle(fontSize: 14)),
                  const Spacer(),
                  Switch(
                    value: _draft.inStock,
                    activeColor: c.orange,
                    onChanged: (v) =>
                        setState(() => _draft = _draft.copyWith(inStock: v)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              TextButton(
                onPressed: () {
                  ref.read(filtersProvider.notifier).reset();
                  Navigator.pop(context);
                },
                child: const Text('Сбросить'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  ref.read(filtersProvider.notifier).apply(_draft);
                  Navigator.pop(context);
                },
                child: const Text('Показать результаты'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: context.colors.faint)),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? c.ink : c.card,
          border: Border.all(color: selected ? c.ink : c.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? c.paper : c.ink)),
      ),
    );
  }
}
