import 'package:shared_preferences/shared_preferences.dart';

import 'client_preferences.dart';

class AppPreferences {
  AppPreferences._(this._prefs);

  static const _serverUrlKey = 'server_url';
  static const _pocketBaseAuthKey = 'pb_auth';
  static const _themePreferenceKey = 'theme_preference';
  static const _languagePreferenceKey = 'language_preference';

  final SharedPreferences _prefs;

  static Future<AppPreferences> create() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferences._(prefs);
  }

  String? get serverUrl {
    final value = _prefs.getString(_serverUrlKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> setServerUrl(String value) =>
      _prefs.setString(_serverUrlKey, value);

  Future<void> clearServerUrl() => _prefs.remove(_serverUrlKey);

  String? get pocketBaseAuth => _prefs.getString(_pocketBaseAuthKey);

  Future<void> savePocketBaseAuth(String value) =>
      _prefs.setString(_pocketBaseAuthKey, value);

  Future<void> clearPocketBaseAuth() => _prefs.remove(_pocketBaseAuthKey);

  AppThemePreference get themePreference =>
      AppThemePreference.fromStorage(_prefs.getString(_themePreferenceKey));

  Future<void> setThemePreference(AppThemePreference value) {
    return _prefs.setString(_themePreferenceKey, value.storageValue);
  }

  AppLanguagePreference get languagePreference =>
      AppLanguagePreference.fromStorage(
        _prefs.getString(_languagePreferenceKey),
      );

  Future<void> setLanguagePreference(AppLanguagePreference value) {
    return _prefs.setString(_languagePreferenceKey, value.storageValue);
  }
}
