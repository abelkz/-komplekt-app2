import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Настройки Firebase для пуш-уведомлений (проект `komplekt-8847a`).
///
/// Файл написан руками, а не сгенерирован `flutterfire configure`, и это
/// не лень: нативные конфиги (`google-services.json`,
/// `GoogleService-Info.plist`) в этом проекте положить некуда — папки
/// `android/` и `ios/` в git не хранятся и генерируются заново каждой
/// сборкой (CLAUDE.md §6.4). Dart-файл в `lib/` переживает
/// `flutter create .`, поэтому настройки живут здесь.
///
/// **Почему эти значения лежат в открытом репозитории.** Они не секретные:
/// ровно тот же набор лежит внутри любого установленного APK — Google так
/// их и задумывал, ключ ограничен пакетом `kz.komplekt.app`. Настоящий
/// секрет — ключ сервисного аккаунта, которым **отправляют** пуши; он
/// живёт только в секретах Supabase (`FCM_PRIVATE_KEY`) и в репозиторий
/// не попадает никогда.
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// Бросает для платформ, которых ещё нет в проекте Firebase. Вызов в
  /// `main.dart` завёрнут в try/catch, так что приложение при этом работает
  /// как раньше — просто без пушей.
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Firebase для веба не настроен: в браузере пуши не нужны',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'iOS-приложение ещё не заведено в Firebase. '
          'Что сделать — в ПУШИ_И_ФУНКЦИИ.md, пункты 1.1–1.4',
        );
      default:
        throw UnsupportedError(
          'Firebase настроен только под Android: $defaultTargetPlatform',
        );
    }
  }

  /// `storageBucket` не указан намеренно: Firebase Storage в проекте не
  /// заведён, файлы лежат в Supabase Storage. Для FCM он не нужен.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBfQf7DLDmJWabLG6gk3fTisrK8UhC-yp4',
    appId: '1:1002346937741:android:3e50c6ff9480a07a1b91c4',
    messagingSenderId: '1002346937741',
    projectId: 'komplekt-8847a',
  );
}
