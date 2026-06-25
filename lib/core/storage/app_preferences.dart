import 'package:shared_preferences/shared_preferences.dart';

import 'client_preferences.dart';

class AppPreferences {
  AppPreferences._(this._prefs);

  static const _serverUrlKey = 'server_url';
  static const _pocketBaseAuthKey = 'pb_auth';
  static const _rememberLoginKey = 'remember_login';
  static const _loginIdentityKey = 'login_identity';
  static const _loginPasswordKey = 'login_password';
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

  bool get rememberLogin => _prefs.getBool(_rememberLoginKey) ?? false;

  SavedLoginCredentials? get savedLoginCredentials {
    if (!rememberLogin) {
      return null;
    }

    final identity = _prefs.getString(_loginIdentityKey)?.trim();
    final password = _prefs.getString(_loginPasswordKey);
    if (identity == null ||
        identity.isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }

    return SavedLoginCredentials(identity: identity, password: password);
  }

  Future<void> saveLoginCredentials({
    required String identity,
    required String password,
  }) async {
    await Future.wait([
      _prefs.setBool(_rememberLoginKey, true),
      _prefs.setString(_loginIdentityKey, identity.trim()),
      _prefs.setString(_loginPasswordKey, password),
    ]);
  }

  Future<void> clearLoginCredentials() async {
    await Future.wait([
      _prefs.setBool(_rememberLoginKey, false),
      _prefs.remove(_loginIdentityKey),
      _prefs.remove(_loginPasswordKey),
    ]);
  }

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

class SavedLoginCredentials {
  const SavedLoginCredentials({required this.identity, required this.password});

  final String identity;
  final String password;
}
