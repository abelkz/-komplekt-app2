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

  /// Инициализация: каналы, разрешения, обработчики. Вызывается в main
  /// после Firebase.initializeApp(). Ошибки не пробрасываются.
  static Future<void> init() async {
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (resp) => _navigate(resp.payload),
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      await FirebaseMessaging.instance.requestPermission();

      // Пуш пришёл, когда приложение открыто → показываем локально
      FirebaseMessaging.onMessage.listen(_showForeground);
      // Тап по пушу (приложение в фоне) → открыть товар
      FirebaseMessaging.onMessageOpenedApp
          .listen((m) => _navigate(m.data['product_id']?.toString()));
      // Запуск из «холодного» состояния по тапу на пуш
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _navigate(initial.data['product_id']?.toString());
      }
      // Обновление токена
      FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);

      _ready = true;
    } catch (e) {
      debugPrint('PushService.init: пуши не настроены ($e)');
    }
  }

  /// Сохранить токен текущего устройства в Supabase (после входа).
  static Future<void> syncToken() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('PushService.syncToken: $e');
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
