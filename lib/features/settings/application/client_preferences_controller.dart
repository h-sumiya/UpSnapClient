import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_preferences.dart';
import '../../../core/storage/client_preferences.dart';

final clientPreferencesControllerProvider =
    NotifierProvider<ClientPreferencesController, ClientPreferences>(
      ClientPreferencesController.new,
    );

class ClientPreferencesController extends Notifier<ClientPreferences> {
  AppPreferences? _preferences;
  bool _initialized = false;

  @override
  ClientPreferences build() {
    if (!_initialized) {
      _initialized = true;
      unawaited(_initialize());
    }

    return const ClientPreferences();
  }

  Future<void> _initialize() async {
    _preferences = await AppPreferences.create();
    state = ClientPreferences(
      themePreference: _preferences!.themePreference,
      languagePreference: _preferences!.languagePreference,
    );
  }

  Future<void> updateThemePreference(AppThemePreference value) async {
    state = state.copyWith(themePreference: value);
    await _preferences?.setThemePreference(value);
  }

  Future<void> updateLanguagePreference(AppLanguagePreference value) async {
    state = state.copyWith(languagePreference: value);
    await _preferences?.setLanguagePreference(value);
  }
}
