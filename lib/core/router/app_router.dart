import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/catalog/presentation/catalog_screen.dart';
import '../../features/catalog/presentation/search_results_screen.dart';
import '../../features/collections/presentation/collections_screen.dart';
import '../../features/favorites/presentation/favorites_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/product/presentation/product_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/supplier_cabinet/presentation/supplier_cabinet_screen.dart';
import '../../features/suppliers_map/presentation/supplier_screen.dart';
import '../../features/suppliers_map/presentation/suppliers_map_screen.dart';
import '../../features/visual_search/presentation/visual_search_screen.dart';
import '../providers/settings_provider.dart';

/// Имена/пути маршрутов в одном месте.
class Routes {
  Routes._();
  static const onboarding = '/onboarding';
  static const auth = '/auth';
  static const home = '/home';
  static const favorites = '/favorites';
  static const collections = '/collections';
  static const profile = '/profile';
  static const map = '/map';
  static const supplierCabinet = '/supplier-cabinet';
  static const notifications = '/notifications';
  static const visualSearch = '/visual-search';
  static String product(String id) => '/product/$id';
  static String catalog(String slug) => '/catalog/$slug';
  static String supplier(String id) => '/supplier/$id';
  static const search = '/search';
}

/// Ключ корневого навигатора — используется и для навигации из пушей.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Мост Riverpod -> Listenable: пересчитываем redirect при смене сессии/настроек
  final refresh = ValueNotifier(0);
  ref
    ..listen(authStateProvider, (_, __) => refresh.value++)
    ..listen(settingsProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final settings = ref.read(settingsProvider);
      final signedIn = ref.read(isSignedInProvider);
      final loc = state.matchedLocation;

      // 1. Сначала онбординг (выбор города)
      if (!settings.onboardingDone) {
        return loc == Routes.onboarding ? null : Routes.onboarding;
      }
      // 2. Затем авторизация
      if (!signedIn) {
        return loc == Routes.auth ? null : Routes.auth;
      }
      // 3. Уже вошёл — не держим на онбординге/авторизации
      if (loc == Routes.onboarding || loc == Routes.auth) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.auth,
        builder: (_, __) => const AuthScreen(),
      ),

      // Основная оболочка с нижней навигацией (4 вкладки)
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.favorites,
                builder: (_, __) => const FavoritesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.collections,
                builder: (_, __) => const CollectionsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.profile,
                builder: (_, __) => const ProfileScreen()),
          ]),
        ],
      ),

      // Полноэкранные маршруты (с кнопкой «назад»)
      GoRoute(
        path: '/product/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => ProductScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/catalog/:slug',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => CatalogScreen(
          slug: state.pathParameters['slug']!,
          title: state.extra as String?,
        ),
      ),
      GoRoute(
        path: Routes.search,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) =>
            SearchResultsScreen(query: state.uri.queryParameters['q'] ?? ''),
      ),
      GoRoute(
        path: Routes.map,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const SuppliersMapScreen(),
      ),
      GoRoute(
        path: Routes.supplierCabinet,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const SupplierCabinetScreen(),
      ),
      GoRoute(
        path: Routes.notifications,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/supplier/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) =>
            SupplierScreen(supplierId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.visualSearch,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const VisualSearchScreen(),
      ),
    ],
  );
});
