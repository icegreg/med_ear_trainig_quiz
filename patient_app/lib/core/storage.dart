import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';

final storageProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Must be overridden in main');
});

class StorageService {
  final SharedPreferences _prefs;

  StorageService(this._prefs);

  // Device token
  String? get deviceToken => _prefs.getString('device_token');
  Future<void> setDeviceToken(String token) =>
      _prefs.setString('device_token', token);
  Future<void> clearDeviceToken() => _prefs.remove('device_token');

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

  double get volumeLevel =>
      _prefs.getDouble('volume_level') ?? kDefaultVolume;
  Future<void> setVolumeLevel(double value) =>
      _prefs.setDouble('volume_level', value);

  bool get isDarkMode => _prefs.getBool('dark_mode') ?? false;
  Future<void> setDarkMode(bool value) => _prefs.setBool('dark_mode', value);

  // API URL (переопределяемый в рантайме)
  String get apiBaseUrl =>
      _prefs.getString('api_base_url') ?? kDefaultApiBaseUrl;
  Future<void> setApiBaseUrl(String url) =>
      _prefs.setString('api_base_url', url);
  Future<void> resetApiBaseUrl() => _prefs.remove('api_base_url');

  bool get isLoggedIn => deviceToken != null;
}
