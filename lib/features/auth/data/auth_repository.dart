import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Телефонная авторизация: шаг 1 — отправка SMS-кода.
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
