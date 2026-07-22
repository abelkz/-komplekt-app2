import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/tape_stripe.dart';
import '../../collections/presentation/collections_providers.dart';
import '../../favorites/presentation/favorites_providers.dart';

/// Оболочка приложения с навигацией-«рулеткой»:
/// тёмная измерительная лента внизу, жёлтый бегунок отмечает активный раздел.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = ['ПОИСК', 'ИЗБРАННОЕ', 'КОМПЛЕКТЫ', 'ПРОФИЛЬ'];
  static const _icons = [
    Icons.search_rounded,
    Icons.favorite_rounded,
    Icons.layers_rounded,
    Icons.person_rounded,
  ];
  static const _hPad = 12.0;
  static const _markerW = 26.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favCount = ref.watch(favoriteIdsProvider).valueOrNull?.length ?? 0;
    final colCount = ref.watch(collectionsItemCountProvider);
    final badges = [0, favCount, colCount, 0];
    final index = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        // «рулетка» всегда тёмная — в обеих темах, это часть бренда
        color: AppColors.brandInk,
        padding: const EdgeInsets.only(top: 14),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // лента с делениями и жёлтым бегунком над активным разделом
              LayoutBuilder(
                builder: (context, constraints) {
                  final tabWidth = (constraints.maxWidth - _hPad * 2) / _tabs.length;
                  final markerLeft =
                      _hPad + tabWidth * (index + 0.5) - _markerW / 2;
                  return SizedBox(
                    height: 18,
                    child: Stack(
                      children: [
                        Positioned(
                          left: _hPad,
                          right: _hPad,
                          top: 2,
                          height: 14,
                          child: const DarkRuler(),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          left: markerLeft,
                          top: 0,
                          width: _markerW,
                          height: 18,
                          child: const ColoredBox(
                            color: AppColors.brandYellow,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(_hPad, 4, _hPad, 4),
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      _NavItem(
                        label: _tabs[i],
                        icon: _icons[i],
                        badge: badges[i],
                        selected: index == i,
                        onTap: () => _go(i),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _go(int index) {
    navigationShell.goBranch(
      index,
      // повторный тап по активной вкладке возвращает к её корню
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

/// Кнопка нижней навигации: иконка + подпись.
/// Высота 58 — так в неё попадает палец даже на ходу (Apple советует
/// не меньше 44 пунктов), а иконка сразу показывает, что это кнопка.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.brandYellow
        : AppColors.brandBone.withValues(alpha: 0.7);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.brandYellow.withValues(alpha: 0.15),
        highlightColor: AppColors.brandYellow.withValues(alpha: 0.08),
        child: SizedBox(
          height: 58,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // иконка со счётчиком в углу
              SizedBox(
                height: 26,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 24, color: color),
                    if (badge > 0)
                      Positioned(
                        right: -9,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 17),
                          decoration: const BoxDecoration(
                            color: AppColors.brandYellow,
                            shape: BoxShape.rectangle,
                          ),
                          child: Text(
                            '$badge',
                            textAlign: TextAlign.center,
                            style: AppTypography.mono(
                              size: 10,
                              weight: FontWeight.w700,
                              color: AppColors.brandInk,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.center,
                style: AppTypography.mono(
                  size: 9,
                  weight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
