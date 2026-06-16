import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../collections/presentation/collections_providers.dart';
import '../../favorites/presentation/favorites_providers.dart';

/// Оболочка приложения с нижней навигацией (Поиск · Избранное · Подборки · Профиль).
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final favCount = ref.watch(favoriteIdsProvider).valueOrNull?.length ?? 0;
    final colCount = ref.watch(collectionsItemCountProvider);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.card,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.search_rounded,
                label: 'Поиск',
                selected: navigationShell.currentIndex == 0,
                onTap: () => _go(0),
              ),
              _NavItem(
                icon: Icons.favorite_border,
                label: 'Избранное',
                badge: favCount,
                selected: navigationShell.currentIndex == 1,
                onTap: () => _go(1),
              ),
              _NavItem(
                icon: Icons.layers_outlined,
                label: 'Подборки',
                badge: colCount,
                selected: navigationShell.currentIndex == 2,
                onTap: () => _go(2),
              ),
              _NavItem(
                icon: Icons.person_outline,
                label: 'Профиль',
                selected: navigationShell.currentIndex == 3,
                onTap: () => _go(3),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = selected ? c.orange : c.faint;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge.count(
                count: badge,
                isLabelVisible: badge > 0,
                backgroundColor: c.orange,
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
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
