import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/providers.dart';
import '../domain/app_user.dart';

/// Поток сессии Supabase (вход/выход) — слушается роутером для redirect.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authState;
});

/// Текущий пользователь авторизован?
final isSignedInProvider = Provider<bool>((ref) {
  ref.watch(authStateProvider); // пересчёт при смене сессии
  return ref.watch(authRepositoryProvider).isSignedIn;
});

/// Профиль текущего пользователя из таблицы users.
final myProfileProvider = FutureProvider<AppUser?>((ref) async {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).myProfile();
});

/// Контроллер действий авторизации (loading/error для форм).
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> signIn(String email, String password) =>
      _run(() => ref
          .read(authRepositoryProvider)
          .signInEmail(email: email, password: password));

  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String city,
    String? phone,
  }) =>
      _run(() => ref.read(authRepositoryProvider).signUpEmail(
            email: email,
            password: password,
            fullName: fullName,
            city: city,
            phone: phone,
          ));

  /// Вход через Google / Apple. Дальше пользователя уводит браузер,
  /// а возврат ловит Supabase — роутер сам перебросит на главную.
  Future<bool> signInWithProvider(OAuthProvider provider) => _run(() =>
      ref.read(authRepositoryProvider).signInWithProvider(provider));

  Future<bool> sendOtp(String phone) =>
      _run(() => ref.read(authRepositoryProvider).sendPhoneOtp(phone));

  Future<bool> verifyOtp(String phone, String token) => _run(() => ref
      .read(authRepositoryProvider)
      .verifyPhoneOtp(phone: phone, token: token));

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
  }

  /// Выполняет действие, прокидывая loading/error в state.
  /// Возвращает true при успехе.
  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);
