import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  late final SharedPreferences _prefs;
  final _secure = const FlutterSecureStorage();

  // Ключи
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kDarkMode = 'dark_mode';
  static const _kCustomApiUrl = 'custom_api_url';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- JWT tokens (secure) ---

  Future<String?> get accessToken => _secure.read(key: _kAccessToken);
  Future<String?> get refreshToken => _secure.read(key: _kRefreshToken);

  Future<void> setTokens({required String access, required String refresh}) async {
    await _secure.write(key: _kAccessToken, value: access);
    await _secure.write(key: _kRefreshToken, value: refresh);
  }

  Future<void> setAccessToken(String token) async {
    await _secure.write(key: _kAccessToken, value: token);
  }

  Future<void> clearTokens() async {
    await _secure.delete(key: _kAccessToken);
    await _secure.delete(key: _kRefreshToken);
  }

  Future<bool> get isLoggedIn async => (await accessToken) != null;

  // --- Preferences ---

  bool get darkMode => _prefs.getBool(_kDarkMode) ?? false;
  set darkMode(bool v) => _prefs.setBool(_kDarkMode, v);

  String? get customApiUrl => _prefs.getString(_kCustomApiUrl);
  set customApiUrl(String? v) {
    if (v == null) {
      _prefs.remove(_kCustomApiUrl);
    } else {
      _prefs.setString(_kCustomApiUrl, v);
    }
  }
}
