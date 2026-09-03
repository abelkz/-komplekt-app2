import 'package:shared_preferences/shared_preferences.dart';

/// Тонкая обёртка над SharedPreferences для пользовательских настроек.
class LocalStore {
  LocalStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<LocalStore> create() async =>
      LocalStore(await SharedPreferences.getInstance());

  // Тема: 'light' | 'dark' | 'system'.
  // По умолчанию — тёмная: премиум-вид «Industrial Noir» из макета.
  // Явный выбор пользователя (переключатель в профиле) сохраняется.
  String get themeMode => _prefs.getString('theme_mode') ?? 'dark';
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

  // ── Модерация пользовательского контента (отзывы) ──
  // Скрытые отзывы и заблокированные авторы — чтобы пользователь мог убрать
  // оскорбительный контент из своей ленты (требование App Store 1.2).
  List<String> get hiddenReviews =>
      _prefs.getStringList('hidden_reviews') ?? const [];
  bool isReviewHidden(String id) => hiddenReviews.contains(id);
  Future<void> hideReview(String id) =>
      _prefs.setStringList('hidden_reviews', {...hiddenReviews, id}.toList());

  List<String> get blockedUsers =>
      _prefs.getStringList('blocked_users') ?? const [];
  bool isUserBlocked(String id) => blockedUsers.contains(id);
  Future<void> blockUser(String id) =>
      _prefs.setStringList('blocked_users', {...blockedUsers, id}.toList());
}
