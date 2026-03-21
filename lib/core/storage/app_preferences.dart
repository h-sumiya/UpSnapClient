import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  AppPreferences._(this._prefs);

  static const _serverUrlKey = 'server_url';
  static const _pocketBaseAuthKey = 'pb_auth';

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
}
