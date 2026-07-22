import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Глобальные настройки приложения: тема, город, статус онбординга.
class Settings {
  const Settings({
    required this.themeMode,
    required this.city,
    required this.onboardingDone,
    this.notifyEnabled = true,
    this.notifyThreshold = 10,
  });

  final ThemeMode themeMode;
  final String city;
  final bool onboardingDone;

  /// Присылать уведомления о снижении цены
  final bool notifyEnabled;

  /// Минимальное снижение цены в процентах, при котором уведомлять
  final int notifyThreshold;

  Settings copyWith({
    ThemeMode? themeMode,
    String? city,
    bool? onboardingDone,
    bool? notifyEnabled,
    int? notifyThreshold,
  }) =>
      Settings(
        themeMode: themeMode ?? this.themeMode,
        city: city ?? this.city,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        notifyEnabled: notifyEnabled ?? this.notifyEnabled,
        notifyThreshold: notifyThreshold ?? this.notifyThreshold,
      );
}

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() {
    final store = ref.read(localStoreProvider);
    return Settings(
      themeMode: _parseTheme(store.themeMode),
      city: store.city ?? 'Астана',
      onboardingDone: store.onboardingDone,
      notifyEnabled: store.notifyEnabled,
      notifyThreshold: store.notifyThreshold,
    );
  }

  static ThemeMode _parseTheme(String v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  void toggleTheme() {
    final next =
        state.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    ref.read(localStoreProvider).setThemeMode(next.name);
    state = state.copyWith(themeMode: next);
  }

  void setCity(String city) {
    ref.read(localStoreProvider).setCity(city);
    state = state.copyWith(city: city);
  }

  /// Настройки уведомлений о цене. Сохраняем на устройстве сразу —
  /// запись в профиль базы делается отдельно и «по возможности».
  void setNotifyPrefs({required bool enabled, required int threshold}) {
    final store = ref.read(localStoreProvider);
    store.setNotifyEnabled(enabled);
    store.setNotifyThreshold(threshold);
    state = state.copyWith(notifyEnabled: enabled, notifyThreshold: threshold);
  }

  void completeOnboarding(String city) {
    final store = ref.read(localStoreProvider);
    store.setCity(city);
    store.setOnboardingDone(true);
    state = state.copyWith(city: city, onboardingDone: true);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);
