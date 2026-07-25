import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import '../../../core/config/supabase_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/app_user.dart';

/// Авторизация и профиль (Supabase Auth + таблица users).
class AuthRepository {
  const AuthRepository();

  /// Поток изменений сессии — на него завязан redirect в роутере.
  Stream<AuthState> get authState => supabase.auth.onAuthStateChange;

  User? get currentUser => supabase.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  /// Регистрация по email. Доп. данные уходят в user_metadata,
  /// откуда триггер handle_new_user заполняет профиль.
  Future<void> signUpEmail({
    required String email,
    required String password,
    required String fullName,
    String city = 'Астана',
    String? phone,
  }) async {
    try {
      await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'city': city,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          'role': 'buyer',
        },
      );
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось зарегистрироваться');
    }
  }

  Future<void> signInEmail({
    required String email,
    required String password,
  }) async {
    try {
      await supabase.auth
          .signInWithPassword(email: email, password: password);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось войти');
    }
  }

  /// Вход через Google / Apple.
  ///
  /// В вебе Supabase возвращает пользователя обратно на ту же страницу
  /// (её адрес обязательно должен быть в Auth → URL Configuration →
  /// Redirect URLs). На телефоне открывается системный браузер и возврат
  /// идёт по схеме kz.komplekt.app://login-callback — она прописывается
  /// в AndroidManifest.xml и Info.plist при сборке.
  static const oauthRedirectScheme = 'kz.komplekt.app://login-callback';

  Future<void> signInWithProvider(OAuthProvider provider) async {
    try {
      await supabase.auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb
            ? '${Uri.base.origin}${Uri.base.path}'
            : oauthRedirectScheme,
        authScreenLaunchMode:
            kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    } catch (e) {
      final text = e.toString();
      // Провайдер не включён в Supabase — самая частая причина
      if (text.contains('not enabled') ||
          text.contains('Unsupported provider')) {
        throw Failure(provider == OAuthProvider.apple
            ? 'Вход через Apple ещё не подключён в Supabase'
            : 'Вход через Google ещё не подключён в Supabase');
      }
      throw mapError(e, fallback: 'Не удалось начать вход');
    }
  }

  /// Номер телефона → служебный email для Supabase Auth.
  ///
  /// SMS-провайдер не подключён (и стоит денег), поэтому вход по номеру
  /// сделан через пароль: номер превращается в `<11 цифр>@example.com`.
  /// Домен example.com зарезервирован RFC 2606 — Supabase принимает его
  /// при проверке MX-записей, в отличие от выдуманных доменов.
  /// Ровно та же схема в веб-кабинете supplier.html — аккаунт общий.
  ///
  /// Возвращает null, если номер не похож на казахстанский.
  static String? phoneToEmail(String raw) {
    final input = raw.trim();
    if (input.contains('@')) return input; // уже email
    var d = input.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11 && d.startsWith('8')) d = '7${d.substring(1)}';
    if (d.length == 10) d = '7$d';
    if (d.length != 11) return null;
    return '$d@example.com';
  }

  /// Телефонная авторизация по SMS-коду: шаг 1 — отправка кода.
  /// Требует подключённого SMS-провайдера в Supabase (Twilio и т.п.).
  Future<void> sendPhoneOtp(String phone) async {
    try {
      await supabase.auth.signInWithOtp(phone: phone);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось отправить код');
    }
  }

  /// Телефонная авторизация: шаг 2 — проверка кода из SMS.
  Future<void> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    try {
      await supabase.auth
          .verifyOTP(phone: phone, token: token, type: OtpType.sms);
    } catch (e) {
      throw mapError(e, fallback: 'Неверный код');
    }
  }

  Future<void> signOut() async => supabase.auth.signOut();

  /// Ссылка, куда вернётся человек по письму сброса пароля.
  /// Веб — на реальный адрес приложения (с учётом подпапки на GitHub Pages),
  /// а не на «Site URL» из настроек; нативка — по схеме приложения.
  String get _resetRedirect {
    if (!kIsWeb) return 'kz.komplekt.app://reset-callback';
    final b = Uri.base; // напр. https://abelkz.github.io/-komplekt-app2/#/auth
    return '${b.origin}${b.path}'; // https://abelkz.github.io/-komplekt-app2/
  }

  /// Отправить письмо для сброса пароля. Работает только для настоящих
  /// email: у входа по телефону адрес служебный (@example.com), туда письмо
  /// не дойдёт — это на экране объясняем отдельно.
  Future<void> sendPasswordReset(String email) async {
    final e = email.trim();
    if (e.isEmpty || !e.contains('@') || e.endsWith('@example.com')) {
      throw const Failure('Введите настоящий email, на который придёт письмо');
    }
    try {
      await supabase.auth.resetPasswordForEmail(e, redirectTo: _resetRedirect);
    } catch (err) {
      throw mapError(err, fallback: 'Не удалось отправить письмо');
    }
  }

  /// Задать новый пароль (после перехода по ссылке из письма — когда уже
  /// есть сессия восстановления).
  Future<void> updatePassword(String newPassword) async {
    if (newPassword.length < 6) {
      throw const Failure('Пароль — минимум 6 символов');
    }
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
    } catch (err) {
      throw mapError(err, fallback: 'Не удалось сменить пароль');
    }
  }

  /// Профиль текущего пользователя из таблицы users.
  Future<AppUser?> myProfile() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    try {
      final row =
          await supabase.from('profiles').select().eq('id', uid).maybeSingle();
      return row == null ? null : AppUser.fromMap(row);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось загрузить профиль');
    }
  }

  Future<void> updateCity(String city) async {
    final uid = currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({'city': city}).eq('id', uid);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось обновить город');
    }
  }

  /// Настройки уведомлений о снижении цены.
  Future<void> updateNotifyPrefs({
    required bool enabled,
    required int threshold,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({
        'notify_price_drops': enabled,
        'notify_threshold': threshold,
      }).eq('id', uid);
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось сохранить настройки');
    }
  }

  /// Удаление аккаунта (RPC delete_my_account → каскадом всё в БД).
  Future<void> deleteAccount() async {
    try {
      await supabase.rpc('delete_my_account');
      await supabase.auth.signOut();
    } catch (e) {
      throw mapError(e, fallback: 'Не удалось удалить аккаунт');
    }
  }
}
