import 'package:shared_preferences/shared_preferences.dart';

/// Тонкая обёртка над SharedPreferences для пользовательских настроек.
class LocalStore {
  LocalStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<LocalStore> create() async =>
      LocalStore(await SharedPreferences.getInstance());

  // Тема: 'light' | 'dark' | 'system'
  String get themeMode => _prefs.getString('theme_mode') ?? 'system';
  Future<void> setThemeMode(String v) => _prefs.setString('theme_mode', v);

  // Выбранный город
  String? get city => _prefs.getString('city');
  Future<void> setCity(String v) => _prefs.setString('city', v);

  // Онбординг пройден
  bool get onboardingDone => _prefs.getBool('onboarding_done') ?? false;
  Future<void> setOnboardingDone(bool v) =>
      _prefs.setBool('onboarding_done', v);

  // Недавние поиски (до 5)
  List<String> get recentSearches =>
      _prefs.getStringList('recent_searches') ?? const [];
  Future<void> setRecentSearches(List<String> v) =>
      _prefs.setStringList('recent_searches', v);
}
