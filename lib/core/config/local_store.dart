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

  // Уведомления о снижении цены: включены и минимальный процент.
  // Держим на устройстве, чтобы выбор сохранялся даже если в базе
  // ещё нет колонок notify_price_drops / notify_threshold.
  bool get notifyEnabled => _prefs.getBool('notify_enabled') ?? true;
  Future<void> setNotifyEnabled(bool v) => _prefs.setBool('notify_enabled', v);

  int get notifyThreshold => _prefs.getInt('notify_threshold') ?? 10;
  Future<void> setNotifyThreshold(int v) => _prefs.setInt('notify_threshold', v);

  // Последний известный статус поставщика — чтобы поймать переход
  // «на проверке» → «одобрен» и показать уведомление один раз.
  String? get supplierStatusSeen => _prefs.getString('supplier_status_seen');
  Future<void> setSupplierStatusSeen(String v) =>
      _prefs.setString('supplier_status_seen', v);

  // Туры-знакомства (подсказки по кнопкам): показаны один раз.
  // id — 'home' (первый вход) или 'supplier' (первый заход в кабинет).
  bool tourSeen(String id) => _prefs.getBool('tour_$id') ?? false;
  Future<void> setTourSeen(String id) => _prefs.setBool('tour_$id', true);

  // Недавние поиски (до 5)
  List<String> get recentSearches =>
      _prefs.getStringList('recent_searches') ?? const [];
  Future<void> setRecentSearches(List<String> v) =>
      _prefs.setStringList('recent_searches', v);
}
