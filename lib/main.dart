import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/config/local_store.dart';
import 'core/config/supabase_client.dart';
import 'core/demo/demo_repositories.dart';
import 'core/providers/data_refresh.dart';
import 'core/providers/providers.dart';
import 'core/providers/settings_provider.dart';
import 'core/push/push_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_providers.dart';
import 'features/notifications/presentation/notifications_providers.dart';

/// Пришли по ссылке сброса пароля? Ловим метку из адреса ДО того, как
/// Supabase обработает и очистит URL. Проверяем на первом кадре.
final bool gPasswordRecoveryLaunch =
    Uri.base.queryParameters['recovery'] == '1' ||
        Uri.base.fragment.contains('type=recovery');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Читаем ключи из .env (никаких секретов в коде)
  await dotenv.load(fileName: '.env');

  final demo = Env.demoMode;

  if (!demo) {
    // 2. Инициализируем Supabase (Auth + Postgres + Storage)
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );

    // 3. Пуши (FCM) — лучшая попытка: без настройки Firebase приложение
    //    работает как обычно, просто без уведомлений.
    try {
      await Firebase.initializeApp();
      await PushService.init();
    } catch (e) {
      debugPrint('Firebase не настроен — пуши отключены: $e');
    }
  } else {
    debugPrint('ДЕМО-РЕЖИМ: встроенные данные, без Supabase/Firebase.');
  }

  // 4. Локальное хранилище (тема, город, недавние поиски)
  final store = await LocalStore.create();

  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        // В демо подменяем все репозитории встроенными данными
        if (demo) ...demoOverrides(),
      ],
      child: const KomplektApp(),
    ),
  );
}

/// Глобальный ключ — показывать уведомление о снижении цены из любого места,
/// даже когда пользователь не на конкретном экране.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class KomplektApp extends ConsumerStatefulWidget {
  const KomplektApp({super.key});

  @override
  ConsumerState<KomplektApp> createState() => _KomplektAppState();
}

class _KomplektAppState extends ConsumerState<KomplektApp>
    with WidgetsBindingObserver {
  RealtimeChannel? _profileChannel;
  RealtimeChannel? _dropsChannel;
  String? _watchedUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _watchForUser(Env.demoMode ? null : supabase.auth.currentUser?.id);
      // Пришли из письма сброса пароля — сразу на экран нового пароля.
      if (gPasswordRecoveryLaunch) {
        rootNavigatorKey.currentContext?.go(Routes.newPassword);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchForUser(null);
    super.dispose();
  }

  /// Живое слежение за своими данными через Realtime:
  ///  • профиль — чтобы включённый тариф появлялся сразу;
  ///  • price_drops — чтобы уведомление о снижении цены на избранный товар
  ///    приходило в момент изменения, а не когда сам зайдёшь в раздел.
  /// Realtime не критичен: без него остаются обновление при возврате и
  /// «потянуть вниз».
  void _watchForUser(String? uid) {
    if (Env.demoMode || uid == _watchedUid) return;

    for (final ch in [_profileChannel, _dropsChannel]) {
      if (ch != null) {
        try {
          supabase.removeChannel(ch);
        } catch (_) {}
      }
    }
    _profileChannel = null;
    _dropsChannel = null;
    _watchedUid = uid;
    if (uid == null) return;

    try {
      _profileChannel = supabase
          .channel('profile:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'profiles',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: uid,
            ),
            callback: (_) {
              if (mounted) ref.invalidate(myProfileProvider);
            },
          )
          .subscribe();

      _dropsChannel = supabase
          .channel('drops:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'price_drops',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: _onPriceDrop,
          )
          .subscribe();
    } catch (_) {/* работаем без Realtime */}
  }

  /// Новое снижение цены на избранный товар: обновляем колокол и показываем
  /// всплывающее уведомление с переходом в раздел.
  void _onPriceDrop(PostgresChangePayload payload) {
    if (!mounted) return;
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadCountProvider);

    final rec = payload.newRecord;
    final name = rec['product_name']?.toString() ?? 'Товар';
    final oldP = (rec['old_price'] as num?)?.toDouble();
    final newP = (rec['new_price'] as num?)?.toDouble();
    final pct = (oldP != null && oldP > 0 && newP != null)
        ? (100 - newP / oldP * 100).round()
        : null;

    scaffoldMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(pct != null
            ? '$name подешевел на $pct%'
            : '$name подешевел'),
        action: SnackBarAction(
          label: 'Смотреть',
          onPressed: () =>
              rootNavigatorKey.currentContext?.push(Routes.notifications),
        ),
      ));
  }

  /// Вернулись в приложение (или к вкладке браузера) — перечитываем данные.
  /// Раньше цену или включённый тариф было видно только после перезапуска.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refreshAppData(ref);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));

    // Регистрируем/чистим FCM-токен при входе/выходе из аккаунта.
    ref.listen(authStateProvider, (_, next) {
      final event = next.valueOrNull?.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        // Пришли по ссылке из письма — ведём на экран смены пароля
        rootNavigatorKey.currentContext?.go(Routes.newPassword);
      } else if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession ||
          event == AuthChangeEvent.tokenRefreshed) {
        PushService.syncToken();
        _watchForUser(next.valueOrNull?.session?.user.id);
      } else if (event == AuthChangeEvent.signedOut) {
        PushService.clearToken();
        _watchForUser(null);
      }
    });

    return MaterialApp.router(
      title: 'КОМПЛЕКТ',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,

      // Русский интерфейс с заделом под казахский
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('kk'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
