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
    required this.hasApns,
    required this.hasToken,
    required this.registered,
    this.error,
  });

  /// Текст исключения, если проверка сорвалась. Показывается прямо в
  /// интерфейсе: без него остаётся только «что-то не так», а сама причина
  /// уходит в debugPrint, которого на телефоне никто не увидит.
  final String? error;

  final bool firebaseReady;

  /// null — состояние выяснить не удалось.
  final AuthorizationStatus? permission;

  /// Выдала ли Apple APNs-токен. null — не iOS, там ступени нет.
  ///
  /// Отдельная ступень нужна, чтобы различить две совершенно разные поломки,
  /// которые снаружи выглядят одинаково («нет токена»): Apple не пустила
  /// приложение в APNs (entitlement, профиль подписи, сеть) — или пустила,
  /// но Firebase не смог обменять её токен на свой (APNs-ключ, Team ID,
  /// bundle id в консоли). Чинятся они в разных местах.
  final bool? hasApns;

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
  ///
  /// Причина (`error`) приписывается к ЛЮБОЙ несработавшей ступени. В первой
  /// редакции она выводилась только там, где сорвалась проверка разрешения,
  /// и сборка 33 показала, во что это обходится: ступень «нет токена»
  /// назвала правдоподобную догадку про APNs-ключ в Firebase, хотя ключ был
  /// на месте, а настоящий текст исключения так и остался в debugPrint.
  /// Диагностика, которая угадывает вместо того, чтобы показать ответ
  /// системы, стоит дороже, чем её отсутствие.
  String get label {
    final why = error;
    String withWhy(String text) => why == null ? text : '$text ($why)';

    if (!firebaseReady) {
      return 'Firebase не настроен в этой сборке — уведомления не придут';
    }
    // Успех проверяем первым: если токен получен и записан, цепочка на
    // телефоне работает — что бы ни ответила проверка разрешения. Иначе
    // её осечка выдавала бы тревогу поверх исправного состояния.
    if (hasToken && registered) {
      return 'Устройство зарегистрировано, уведомления будут приходить';
    }
    switch (permission) {
      case AuthorizationStatus.notDetermined:
        return 'Разрешение ещё не запрашивалось. Перезапустите приложение — '
            'система спросит при следующем открытии';
      case AuthorizationStatus.denied:
        return 'Уведомления отключены для приложения. Включить: Настройки '
            'телефона → КОМПЛЕКТ → Уведомления';
      case null:
        return withWhy('Не удалось проверить разрешение');
      default:
        break;
    }
    if (hasApns == false) {
      return withWhy('Apple не выдала APNs-токен — без него Firebase не выдаст '
          'свой. Нажмите «Повторить»');
    }
    if (!hasToken) {
      return withWhy('APNs-токен есть, но Firebase не выдал свой — '
          'смотреть APNs-ключ и Team ID в консоли Firebase');
    }
    if (!registered) {
      return withWhy('Токен получен, но не записан в базу — нужен вход '
          'в аккаунт');
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

      // Флаг ставим здесь, а не после настройки локальных уведомлений.
      // `_ready` означает «Firebase Messaging пригоден» — а он уже поднят
      // в main.dart до вызова этого метода. Плагин локальных уведомлений
      // ниже нужен только чтобы ПОКАЗАТЬ уведомление при открытом
      // приложении, к выдаче токена он отношения не имеет. Пока флаг
      // стоял после него, любая его осечка молча отменяла регистрацию
      // токена: syncToken() выходил на первой строке, а строка состояния
      // винила Firebase, который был в полном порядке.
      _ready = true;

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

  /// Дождаться APNs-токена. Только iOS: на других платформах ступени нет.
  ///
  /// Apple выдаёт APNs-токен НЕ сразу: регистрация уходит в сеть и отвечает
  /// через секунду-другую после того, как человек нажал «Разрешить». А запрос
  /// FCM-токена без APNs-токена на iOS падает с `apns-token-not-set` —
  /// Firebase нечего обменивать. `init()` делал ровно это: спрашивал
  /// разрешение и тут же звал `getToken()`, попадая в эту самую паузу.
  /// Ошибка гасилась, второй попытки не было, и устройство оставалось
  /// незарегистрированным до следующего запуска — где повторялось то же
  /// самое. Поэтому здесь опрос, а не один вызов.
  static Future<String?> _awaitApnsToken() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return null;
    final until = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(until)) {
      try {
        final apns = await FirebaseMessaging.instance
            .getAPNSToken()
            .timeout(const Duration(seconds: 5));
        if (apns != null) return apns;
      } catch (e) {
        debugPrint('PushService._awaitApnsToken: $e');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return null;
  }

  /// Сохранить токен текущего устройства в Supabase (после входа).
  static Future<void> syncToken() async {
    if (!_ready) return;
    try {
      // На iOS сначала дожидаемся APNs-токена — см. комментарий выше.
      // Если он так и не пришёл, всё равно пробуем: пусть getToken()
      // сам скажет, что не так, а не молчит из-за нашей проверки.
      await _awaitApnsToken();
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

  /// Повторить регистрацию по кнопке в настройках.
  ///
  /// Нужна потому, что первая попытка идёт один раз за запуск и упирается
  /// в чужие сроки: сеть, ответ APNs, момент, когда человек нажал
  /// «Разрешить». Без кнопки единственный способ попробовать снова —
  /// перезапустить приложение, и человеку это неоткуда узнать.
  static Future<void> retry() async {
    if (!_ready) return;
    try {
      await FirebaseMessaging.instance
          .requestPermission()
          .timeout(const Duration(minutes: 2));
    } catch (e) {
      debugPrint('PushService.retry/разрешение: $e');
    }
    await syncToken();
  }

  /// Проверить всю цепочку доставки. Ошибки не поднимаем: экран настроек
  /// должен открыться в любом случае, даже если Firebase вовсе нет.
  static Future<PushStatus> status() async {
    if (!_ready) {
      return const PushStatus(
        firebaseReady: false,
        permission: null,
        hasApns: null,
        hasToken: false,
        registered: false,
      );
    }
    // Каждый шаг в своём try. Раньше все три стояли в одном, и осечка
    // первого прятала два остальных: экран писал «не удалось проверить
    // разрешение», хотя токен мог быть получен и записан. Диагностика,
    // которая обрывается на первой же неудаче, показывает не состояние
    // цепочки, а только место падения.
    //
    // Таймауты обязательны: этот метод рисует экран настроек, и зависший
    // вызов оставил бы строку пустой навсегда.
    AuthorizationStatus? permission;
    String? error;

    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings()
          .timeout(const Duration(seconds: 10));
      permission = settings.authorizationStatus;
    } catch (e) {
      debugPrint('PushService.status/разрешение: $e');
      error = 'разрешение — ${_short(e)}';
    }

    // APNs-ступень проверяем до FCM-токена: она первая в цепочке, и её
    // ответ говорит, в чьём хозяйстве искать — Apple или Firebase.
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    bool? hasApns;
    if (isIos) {
      try {
        final apns = await FirebaseMessaging.instance
            .getAPNSToken()
            .timeout(const Duration(seconds: 10));
        hasApns = apns != null;
      } catch (e) {
        debugPrint('PushService.status/APNs: $e');
        error ??= 'APNs — ${_short(e)}';
        hasApns = false;
      }
    }

    String? token;
    try {
      token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('PushService.status/токен: $e');
      error ??= 'токен — ${_short(e)}';
    }

    var registered = false;
    if (token != null && supabase.auth.currentUser != null) {
      try {
        final row = await supabase
            .from('device_tokens')
            .select('token')
            .eq('token', token)
            .maybeSingle();
        registered = row != null;
      } catch (e) {
        debugPrint('PushService.status/база: $e');
        error ??= 'база — ${_short(e)}';
      }
    }

    return PushStatus(
      firebaseReady: true,
      permission: permission,
      hasApns: hasApns,
      hasToken: token != null,
      registered: registered,
      error: error,
    );
  }

  /// Короткая запись исключения для показа в интерфейсе: тип и первая
  /// строка сообщения. Полный стек здесь не нужен — нужен опознавательный
  /// знак, по которому понятно, куда смотреть.
  static String _short(Object e) {
    final text = e.toString().replaceAll('\n', ' ');
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
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
