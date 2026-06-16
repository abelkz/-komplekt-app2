import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Доступ к переменным окружения из файла `.env`.
/// Никаких ключей в коде — всё читается отсюда (см. .env.example).
class Env {
  Env._();

  static String get supabaseUrl => _require('SUPABASE_URL');
  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

  static String get defaultCity => dotenv.maybeGet('DEFAULT_CITY') ?? 'Астана';

  static double get defaultLat =>
      double.tryParse(dotenv.maybeGet('DEFAULT_LAT') ?? '') ?? 51.1280;
  static double get defaultLng =>
      double.tryParse(dotenv.maybeGet('DEFAULT_LNG') ?? '') ?? 71.4304;

  /// Демо-режим: приложение работает на встроенных данных, без Supabase и
  /// Firebase. Включается флагом DEMO_MODE=true ИЛИ автоматически, если
  /// SUPABASE_URL ещё не заполнен реальным значением (placeholder).
  static bool get demoMode {
    final flag = (dotenv.maybeGet('DEMO_MODE') ?? '').toLowerCase();
    if (flag == 'true' || flag == '1' || flag == 'yes') return true;
    final url = dotenv.maybeGet('SUPABASE_URL') ?? '';
    return url.isEmpty || url.contains('your-project-ref');
  }

  /// Бросает понятную ошибку, если ключ забыли прописать в .env.
  static String _require(String key) {
    final value = dotenv.maybeGet(key);
    if (value == null || value.isEmpty) {
      throw StateError(
        'В файле .env не задан ключ "$key". '
        'Скопируйте .env.example в .env и впишите значения.',
      );
    }
    return value;
  }
}
