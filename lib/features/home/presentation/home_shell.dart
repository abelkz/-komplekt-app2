import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/onboarding/feature_tour.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../collections/presentation/collections_providers.dart';
import '../../favorites/presentation/favorites_providers.dart';

/// Оболочка приложения с нижней навигацией «Industrial Noir»:
/// приподнятая панель с тонкой верхней линией и золотой пилюлей на активном
/// разделе.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = ['Поиск', 'Избранное', 'Коллекции', 'Профиль'];
  static const _icons = [
    Icons.search_rounded,
    Icons.favorite_rounded,
    Icons.folder_special_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final favCount = ref.watch(favoriteIdsProvider).valueOrNull?.length ?? 0;
    final colCount = ref.watch(collectionsItemCountProvider);
    final badges = [0, favCount, colCount, 0];
    final index = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        key: TourKeys.navBar,
        decoration: BoxDecoration(
          color: c.card,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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

/// Кнопка нижней навигации: иконка + подпись. Активный раздел — золотая
/// пилюля с тёмным текстом; остальные — приглушённые.
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
    final c = context.colors;
    final content = selected ? AppColors.brandInk : c.faint;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // иконка со счётчиком в углу
              SizedBox(
                height: 26,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 24, color: content),
                    if (badge > 0)
                      Positioned(
                        right: -9,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 17),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.brandInk : c.accent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '$badge',
                            textAlign: TextAlign.center,
                            style: AppTypography.mono(
                              size: 10,
                              weight: FontWeight.w700,
                              color: selected ? c.accent : AppColors.brandInk,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.center,
                style: AppTypography.sectionLabel(color: content).copyWith(
                  fontSize: 10,
                  letterSpacing: 0.2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
