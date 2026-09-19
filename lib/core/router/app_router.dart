import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_screen.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/auth/presentation/new_password_screen.dart';
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
import '../../features/subscription/data/subscription_repository.dart';
import '../../features/subscription/presentation/plans_screen.dart';
import '../../features/supplier_cabinet/presentation/supplier_cabinet_screen.dart';
import '../../features/supplier_cabinet/presentation/supplier_location_screen.dart';
import '../../features/suppliers_map/presentation/supplier_screen.dart';
import '../../features/suppliers_map/presentation/suppliers_map_screen.dart';
import '../../features/visual_search/presentation/visual_search_screen.dart';
import '../providers/settings_provider.dart';

/// Имена/пути маршрутов в одном месте.
class Routes {
  Routes._();
  static const onboarding = '/onboarding';
  static const auth = '/auth';
  static const newPassword = '/new-password';
  static const home = '/home';
  static const favorites = '/favorites';
  static const collections = '/collections';
  static const profile = '/profile';
  static const map = '/map';
  static const supplierCabinet = '/supplier-cabinet';
  static const supplierLocation = '/supplier-cabinet/location';
  static const notifications = '/notifications';
  static const visualSearch = '/visual-search';
  static const admin = '/admin';

  /// Платный тариф. `for=supplier` — предложение для компаний,
  /// без параметра — для дизайнеров и прорабов.
  static String plans({bool forSupplier = false, String? supplierId}) =>
      '/pro?for=${forSupplier ? 'supplier' : 'client'}'
      '${supplierId != null ? '&company=$supplierId' : ''}';
  static String product(String id) => '/product/$id';
  static String catalog(String slug) => '/catalog/$slug';
  static String supplier(String id) => '/supplier/$id';
  static const search = '/search';
}

/// Ключ корневого навигатора — используется и для навигации из пушей.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Маршруты, которым обязательно нужен аккаунт: личный кабинет, уведомления,
/// оплата, админка. Всё остальное — каталог, поиск, карта, карточки товаров и
/// витрины поставщиков — гость смотрит свободно.
///
/// Вкладок «Избранное» и «Подборки» здесь нет намеренно: вместо переброса на
/// вход они показывают предложение войти прямо на своём месте, не выбрасывая
/// человека из вкладки (см. SignInRequired).
/// Сравнение только точное. Был `startsWith('/pro')` — под него попадали
/// `/product/:id` и `/profile`, то есть карточка товара и вкладка профиля
/// считались платным разделом и гостя с них выбрасывало. Префиксы здесь
/// опасны: пути приложения начинаются одинаково.
@visibleForTesting
bool needsAccount(String location) =>
    location == Routes.supplierCabinet ||
    location == Routes.supplierLocation ||
    location == Routes.notifications ||
    location == Routes.admin ||
    location == '/pro';

/// Куда вернуться после онбординга или входа.
///
/// Пустой `from` — значит человек пришёл сам, без ссылки: ведём на главную.
/// Отдельно отсекаем сам онбординг и корень: попасть туда «обратно» значит
/// закольцевать переход и повесить приложение на белом экране.
@visibleForTesting
String backTo(String? from) {
  if (from == null || from.isEmpty) return Routes.home;
  final target = Uri.decodeComponent(from);
  if (target == '/' || target.startsWith(Routes.onboarding)) {
    return Routes.home;
  }
  return target;
}

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
    // Любой неизвестный адрес (обрывки после входа/ссылок) — на главную,
    // а не «Page Not Found».
    errorBuilder: (_, __) => const _RedirectHome(),
    redirect: (context, state) {
      final settings = ref.read(settingsProvider);
      final signedIn = ref.read(isSignedInProvider);
      final loc = state.matchedLocation;

      // 0a. Возврат от Google/Apple и писем приходит на корень «/», для
      // которого маршрута нет (были «no routes for location: /»). Отправляем
      // на главную — дальше сессия/онбординг разрулят ниже.
      if (loc == '/') return Routes.home;

      // 0b. Смену пароля из письма пропускаем всегда — иначе онбординг/вход
      // перехватит переход и человек не задаст новый пароль.
      if (loc == Routes.newPassword) return null;

      // 1. Сначала онбординг (выбор города).
      //
      //    Исходный адрес несём с собой в ?from — так же, как это уже сделано
      //    для входа. Без этого ссылка на товар, присланная человеку, который
      //    открывает приложение впервые, приводила его на выбор города, а
      //    оттуда на главную: товар, ради которого ссылку и прислали,
      //    терялся по дороге. Проверено на вебе 19.09.2026.
      if (!settings.onboardingDone) {
        if (loc == Routes.onboarding) return null;
        final from = Uri.encodeComponent(state.uri.toString());
        return '${Routes.onboarding}?from=$from';
      }
      // 2. Каталог, поиск, карта и карточки товаров открыты гостю: человек
      //    должен увидеть, что внутри, прежде чем его просят регистрироваться.
      //    Аккаунт спрашиваем только там, где без него нечего показать.
      if (!signedIn && needsAccount(loc)) {
        final from = Uri.encodeComponent(state.uri.toString());
        return '${Routes.auth}?from=$from';
      }
      // 3. Уже вошёл — не держим на онбординге/авторизации. Если пришли
      //    сюда за чем-то конкретным (from), возвращаем туда.
      //
      //    Проверка signedIn здесь обязательна: без неё редирект уводил с
      //    /auth на /home и гостя тоже, то есть открыть вход было нельзя
      //    вообще — ни кнопкой в «Избранном», ни из профиля.
      if (signedIn && loc == Routes.auth) {
        return backTo(state.uri.queryParameters['from']);
      }
      // 4. Город выбран — уводим с онбординга туда, зачем пришли.
      if (loc == Routes.onboarding) {
        return backTo(state.uri.queryParameters['from']);
      }
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
      GoRoute(
        path: Routes.newPassword,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const NewPasswordScreen(),
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
        path: Routes.supplierLocation,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const SupplierLocationScreen(),
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
        path: Routes.admin,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const AdminScreen(),
      ),
      GoRoute(
        path: Routes.visualSearch,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const VisualSearchScreen(),
      ),
      GoRoute(
        path: '/pro',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => PlansScreen(
          kind: state.uri.queryParameters['for'] == 'supplier'
              ? PlanKind.supplier
              : PlanKind.client,
          supplierId: state.uri.queryParameters['company'],
        ),
      ),
    ],
  );
});

/// Молча уводит на главную вместо экрана «страница не найдена».
class _RedirectHome extends StatelessWidget {
  const _RedirectHome();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.go(Routes.home);
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }
}
