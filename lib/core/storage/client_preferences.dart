import 'package:flutter/material.dart';

enum AppThemePreference {
  system('system'),
  light('light'),
  dark('dark');

  const AppThemePreference(this.storageValue);

  final String storageValue;

  ThemeMode get themeMode => switch (this) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };

  static AppThemePreference fromStorage(String? value) {
    return AppThemePreference.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AppThemePreference.system,
    );
  }
}

enum AppLanguagePreference {
  system('system', null),
  english('en', Locale('en')),
  japanese('ja', Locale('ja'));

  const AppLanguagePreference(this.storageValue, this.locale);

  final String storageValue;
  final Locale? locale;

  static AppLanguagePreference fromStorage(String? value) {
    return AppLanguagePreference.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AppLanguagePreference.system,
    );
  }
}

class ClientPreferences {
  const ClientPreferences({
    this.themePreference = AppThemePreference.system,
    this.languagePreference = AppLanguagePreference.system,
  });

  final AppThemePreference themePreference;
  final AppLanguagePreference languagePreference;

  ThemeMode get themeMode => themePreference.themeMode;
  Locale? get locale => languagePreference.locale;

  ClientPreferences copyWith({
    AppThemePreference? themePreference,
    AppLanguagePreference? languagePreference,
  }) {
    return ClientPreferences(
      themePreference: themePreference ?? this.themePreference,
      languagePreference: languagePreference ?? this.languagePreference,
    );
  }
}
