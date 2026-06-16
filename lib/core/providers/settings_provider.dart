import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Глобальные настройки приложения: тема, город, статус онбординга.
class Settings {
  const Settings({
    required this.themeMode,
    required this.city,
    required this.onboardingDone,
  });

  final ThemeMode themeMode;
  final String city;
  final bool onboardingDone;

  Settings copyWith({ThemeMode? themeMode, String? city, bool? onboardingDone}) =>
      Settings(
        themeMode: themeMode ?? this.themeMode,
        city: city ?? this.city,
        onboardingDone: onboardingDone ?? this.onboardingDone,
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

  void completeOnboarding(String city) {
    final store = ref.read(localStoreProvider);
    store.setCity(city);
    store.setOnboardingDone(true);
    state = state.copyWith(city: city, onboardingDone: true);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);
