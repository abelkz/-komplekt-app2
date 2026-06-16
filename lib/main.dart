import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/config/local_store.dart';
import 'core/demo/demo_repositories.dart';
import 'core/providers/providers.dart';
import 'core/providers/settings_provider.dart';
import 'core/push/push_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_providers.dart';

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

class KomplektApp extends ConsumerWidget {
  const KomplektApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));

    // Регистрируем/чистим FCM-токен при входе/выходе из аккаунта.
    ref.listen(authStateProvider, (_, next) {
      final event = next.valueOrNull?.event;
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession ||
          event == AuthChangeEvent.tokenRefreshed) {
        PushService.syncToken();
      } else if (event == AuthChangeEvent.signedOut) {
        PushService.clearToken();
      }
    });

    return MaterialApp.router(
      title: 'КОМПЛЕКТ',
      debugShowCheckedModeBanner: false,
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
