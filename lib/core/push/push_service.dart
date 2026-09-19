import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../config/supabase_client.dart';
import '../router/app_router.dart';

/// Фоновый обработчик пушей (top-level + entry-point — требование FCM).
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // Инициализируем Firebase в фоновом изоляте (на случай холодного старта).
  await Firebase.initializeApp();
  // Системное уведомление FCM покажет сам; здесь можно вести аналитику.
}

/// Что с пушами на этом устройстве — для экрана настроек уведомлений.
///
/// Появилось не от хорошей жизни: вся цепочка (Firebase → разрешение →
/// токен → строка в device_tokens) при любой поломке молчит, потому что
/// ошибки гасятся в try/catch и уходят в debugPrint, которого на телефоне
/// не видно. Из-за этого уведомления не работали с самого первого релиза,
/// и заметить это было нечем — в базе просто не появлялось токенов.
class PushStatus {
  const PushStatus({
    required this.firebaseReady,
    required this.permission,
    required this.hasToken,
    required this.registered,
  });

  final bool firebaseReady;

  /// null — состояние выяснить не удалось.
  final AuthorizationStatus? permission;

  final bool hasToken;

  /// Токен доехал до таблицы device_tokens — значит серверу есть куда слать.
  final bool registered;

  bool get allowed =>
      permission == AuthorizationStatus.authorized ||
      permission == AuthorizationStatus.provisional;

  bool get ok => firebaseReady && allowed && hasToken && registered;

  /// Первая же несработавшая ступень — её и показываем: чинить всё равно
  /// придётся снизу вверх.
  ///
  /// «Не спрашивали» и «запретили» разделены нарочно: лечатся они по-разному,
  /// а раньше обе ступени показывали «запрещены в настройках телефона» — и
  /// человек шёл искать переключатель, которого там ещё нет.
  String get label {
    if (!firebaseReady) {
      return 'Firebase не настроен в этой сборке — уведомления не придут';
    }
    switch (permission) {
      case AuthorizationStatus.notDetermined:
        return 'Разрешение ещё не запрашивалось. Перезапустите приложение — '
            'система спросит при следующем открытии';
      case AuthorizationStatus.denied:
        return 'Уведомления отключены для приложения. Включить: Настройки '
            'телефона → КОМПЛЕКТ → Уведомления';
      case null:
        return 'Не удалось проверить разрешение на уведомления';
      default:
        break;
    }
    if (!hasToken) {
      return 'Устройство не получило токен: на iOS так бывает без APNs-ключа '
          'в Firebase';
    }
    if (!registered) {
      return 'Токен получен, но не записан в базу — нужен вход в аккаунт';
    }
    return 'Устройство зарегистрировано, уведомления будут приходить';
  }
}

/// Пуш-уведомления о снижении цены (FCM + локальные уведомления).
/// Все методы безопасны: если Firebase не настроен, они тихо ничего не делают,
/// чтобы остальное приложение работало без пушей.
class PushService {
  PushService._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'price_alerts',
    'Снижение цен',
    description: 'Уведомления о снижении цены на товары из избранного',
    importance: Importance.high,
  );

  static bool _ready = false;

  /// Инициализация: каналы, разрешения, обработчики.
  ///
  /// Вызывается из `main.dart` **после `runApp`** и без `await` — см.
  /// комментарий там. Каждый await здесь ограничен по времени: зависший
  /// вызов не выбрасывает исключение, и без таймаута он навсегда оставил
  /// бы `_ready` в false, а токен — незарегистрированным.
  ///
  /// Ошибки наружу не отдаём: без пушей приложение работает как обычно.
  static Future<void> init() async {
    try {
      // Сначала — всё синхронное. Обработчики должны стоять до первого
      // возможного пуша, и они не зависят от разрешения пользователя.
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      // Пуш пришёл, когда приложение открыто → показываем локально
      FirebaseMessaging.onMessage.listen(_showForeground);
      // Тап по пушу (приложение в фоне) → открыть товар
      FirebaseMessaging.onMessageOpenedApp
          .listen((m) => _navigate(m.data['product_id']?.toString()));
      // Обновление токена
      FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);

      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Разрешение здесь НЕ просим: по умолчанию DarwinInitializationSettings
          // запрашивает его само, и тогда окно показывают двое — этот плагин
          // и FirebaseMessaging. iOS спрашивает один раз, ответ достаётся
          // тому, кто успел первым, а второй видит уже готовый статус.
          // Просить должен кто-то один, и это FirebaseMessaging ниже:
          // именно от него зависит выдача токена.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (resp) => _navigate(resp.payload),
      ).timeout(const Duration(seconds: 15));

      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel)
          .timeout(const Duration(seconds: 15));

      // Механика поднята — дальше всё необязательное. Ставим флаг здесь,
      // чтобы он не зависел от того, как быстро человек ответит на запрос
      // разрешения: ждать можно минуту, а токен нужен независимо.
      _ready = true;

      // Запрос разрешения ждёт ответа человека, поэтому срок щедрый.
      await FirebaseMessaging.instance
          .requestPermission()
          .timeout(const Duration(minutes: 2));

      // Запуск из «холодного» состояния по тапу на пуш
      final initial = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 15));
      if (initial != null) {
        _navigate(initial.data['product_id']?.toString());
      }
    } catch (e) {
      debugPrint('PushService.init: пуши настроены не полностью ($e)');
    }

    // Токен сохраняем в любом случае, если вход уже состоялся: слушатель
    // авторизации в main.dart мог сработать раньше, чем поднялась эта
    // механика, и тогда его вызов syncToken() вышел вхолостую.
    await syncToken();
  }

  /// Сохранить токен текущего устройства в Supabase (после входа).
  static Future<void> syncToken() async {
    if (!_ready) return;
    try {
      // Таймаут: на iOS getToken() ждёт, пока система выдаст APNs-токен,
      // и без ключа в Firebase или без разрешения может не ответить вовсе.
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 20));
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('PushService.syncToken: $e');
    }
  }

  /// Проверить всю цепочку доставки. Ошибки не поднимаем: экран настроек
  /// должен открыться в любом случае, даже если Firebase вовсе нет.
  static Future<PushStatus> status() async {
    if (!_ready) {
      return const PushStatus(
        firebaseReady: false,
        permission: null,
        hasToken: false,
        registered: false,
      );
    }
    try {
      // Таймауты и здесь: эту проверку рисует экран настроек, и зависший
      // вызов оставил бы строку состояния пустой навсегда.
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings()
          .timeout(const Duration(seconds: 10));
      final permission = settings.authorizationStatus;
      final allowed = permission == AuthorizationStatus.authorized ||
          permission == AuthorizationStatus.provisional;
      // Токен запрашиваем только при выданном разрешении: на iOS без него
      // getToken() ждёт APNs-токен, которого не будет, и упирается в таймаут.
      final token = allowed
          ? await FirebaseMessaging.instance
              .getToken()
              .timeout(const Duration(seconds: 20))
          : null;

      var registered = false;
      if (token != null && supabase.auth.currentUser != null) {
        final row = await supabase
            .from('device_tokens')
            .select('token')
            .eq('token', token)
            .maybeSingle();
        registered = row != null;
      }
      return PushStatus(
        firebaseReady: true,
        allowed: allowed,
        hasToken: token != null,
        registered: registered,
      );
    } catch (e) {
      debugPrint('PushService.status: $e');
      return const PushStatus(
        firebaseReady: true,
        allowed: false,
        hasToken: false,
        registered: false,
      );
    }
  }

  /// Удалить токен (при выходе из аккаунта).
  static Future<void> clearToken() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await supabase.from('device_tokens').delete().eq('token', token);
      }
    } catch (e) {
      debugPrint('PushService.clearToken: $e');
    }
  }

  static Future<void> _saveToken(String token) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('device_tokens').upsert({
        'token': token,
        'user_id': uid,
        // defaultTargetPlatform вместо dart:io — работает и в вебе
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('PushService._saveToken: $e');
    }
  }

  static void _showForeground(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    _local.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['product_id']?.toString(),
    );
  }

  /// Открыть карточку товара по productId из пуша.
  static void _navigate(String? productId) {
    if (productId == null || productId.isEmpty) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    ctx.push(Routes.product(productId));
  }
}
