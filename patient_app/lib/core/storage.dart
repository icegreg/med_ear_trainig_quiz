import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';

final storageProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Must be overridden in main');
});

class StorageService {
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  // Кэш токена и хэша ПИН в памяти (secure storage — async)
  String? _deviceTokenCache;
  String? _pinHashCache;
  String? _pinSaltCache;

  StorageService(this._prefs, this._secure);

  // Device token — хранится в secure storage
  String? get deviceToken => _deviceTokenCache;

  /// Загружает токен и ПИН из secure storage в память.
  Future<void> loadSecureData() async {
    try {
      _deviceTokenCache = await _secure.read(key: 'device_token');
      _pinHashCache = await _secure.read(key: 'pin_hash');
      _pinSaltCache = await _secure.read(key: 'pin_salt');
    } catch (_) {
      // Битое/несовместимое хранилище (смена ключа шифрования, другая версия пакета).
      // Сбрасываем, чтобы приложение запустилось — пользователь перелогинится.
      try {
        await _secure.deleteAll();
      } catch (_) {}
      _deviceTokenCache = null;
      _pinHashCache = null;
      _pinSaltCache = null;
    }
  }

  Future<void> setDeviceToken(String token) async {
    await _secure.write(key: 'device_token', value: token);
    _deviceTokenCache = token;
  }

  Future<void> clearDeviceToken() async {
    await _secure.delete(key: 'device_token');
    _deviceTokenCache = null;
    await clearTokenExpiry();
  }

  // Срок жизни токена (ISO 8601, выдаётся сервером)
  DateTime? get tokenExpiresAt {
    final raw = _prefs.getString('token_expires_at');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setTokenExpiresAt(String iso) =>
      _prefs.setString('token_expires_at', iso);

  Future<void> clearTokenExpiry() => _prefs.remove('token_expires_at');

  bool get isTokenExpired {
    final exp = tokenExpiresAt;
    return exp != null && DateTime.now().isAfter(exp);
  }

  // --- ПИН-код быстрого входа (хэш в secure storage) ---

  bool get hasPin => _pinHashCache != null;

  String _hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String pin) async {
    final rng = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => rng.nextInt(256));
    final salt = base64Url.encode(saltBytes);
    final hash = _hashPin(pin, salt);
    await _secure.write(key: 'pin_salt', value: salt);
    await _secure.write(key: 'pin_hash', value: hash);
    _pinSaltCache = salt;
    _pinHashCache = hash;
  }

  Future<void> clearPin() async {
    await _secure.delete(key: 'pin_hash');
    await _secure.delete(key: 'pin_salt');
    _pinHashCache = null;
    _pinSaltCache = null;
  }

  bool verifyPin(String pin) {
    final salt = _pinSaltCache;
    final hash = _pinHashCache;
    if (salt == null || hash == null) return false;
    return _hashPin(pin, salt) == hash;
  }

  // Patient ID
  int? get patientId => _prefs.getInt('patient_id');
  Future<void> setPatientId(int id) => _prefs.setInt('patient_id', id);

  // Cached username (для автозаполнения после 401)
  String? get lastUsername => _prefs.getString('last_username');
  Future<void> setLastUsername(String username) =>
      _prefs.setString('last_username', username);

  // Onboarding
  bool get onboardingCompleted => _prefs.getBool('onboarding_completed') ?? false;
  Future<void> setOnboardingCompleted() =>
      _prefs.setBool('onboarding_completed', true);

  // Settings
  double get batteryThreshold =>
      _prefs.getDouble('battery_threshold') ?? kDefaultBatteryThreshold;
  Future<void> setBatteryThreshold(double value) =>
      _prefs.setDouble('battery_threshold', value);

  bool get isDarkMode => _prefs.getBool('dark_mode') ?? false;
  Future<void> setDarkMode(bool value) => _prefs.setBool('dark_mode', value);

  // API URL (переопределяемый в рантайме)
  String get apiBaseUrl =>
      _prefs.getString('api_base_url') ?? kDefaultApiBaseUrl;
  Future<void> setApiBaseUrl(String url) =>
      _prefs.setString('api_base_url', url);
  Future<void> resetApiBaseUrl() => _prefs.remove('api_base_url');

  bool get isLoggedIn => _deviceTokenCache != null && !isTokenExpired;
}
