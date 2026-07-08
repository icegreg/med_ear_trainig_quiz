import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, appFlavor;

/// Определение окружения (flavor):
///   • Web-сборки задают его через --dart-define=FLAVOR=dev|prod
///     (URL всегда относительный /api — тот же origin, dev-хост недостижим).
///   • Android-сборки используют нативные product flavors (android/app/build.gradle):
///         flutter build apk --flavor dev|preprod|prod
///     имя flavor'а Flutter прокидывает в Dart через appFlavor.
const String _flavorFromDefine = String.fromEnvironment('FLAVOR');

/// Итоговый flavor: приоритет у --dart-define=FLAVOR (web), иначе нативный
/// Android product flavor (--flavor через appFlavor), иначе пусто. Только
/// для логов/отображения — на выбор API-хоста больше не влияет.
final String kFlavor =
    _flavorFromDefine.isNotEmpty ? _flavorFromDefine : (appFlavor ?? '');

/// Канал, через который нативный Android product flavor отдаёт свой — и только
/// свой — API-хост (Gradle buildConfigField API_BASE_URL). За счёт этого в
/// Dart-бинаре нет хостов вовсе, а в каждом APK физически присутствует лишь
/// адрес собственного окружения (Kaiten #67021716).
const MethodChannel _configChannel =
    MethodChannel('com.medear.patient_app/config');

String? _apiBaseUrl;

/// Инициализация конфигурации flavor'а. Вызвать один раз в main() до runApp,
/// чтобы нативный API-хост был получен до первого обращения к API.
Future<void> initFlavorConfig() async {
  if (kIsWeb) {
    _apiBaseUrl = '/api';
    return;
  }
  try {
    final url = await _configChannel.invokeMethod<String>('getApiBaseUrl');
    if (url == null || url.isEmpty) {
      throw StateError('Нативный flavor "$kFlavor" не задал API_BASE_URL');
    }
    _apiBaseUrl = url;
  } on MissingPluginException {
    // Нет нативного канала (unit-тесты / desktop): в debug — эмулятор.
    if (kDebugMode) {
      _apiBaseUrl = 'http://10.0.2.2/api';
      return;
    }
    rethrow;
  }
}

/// Базовый URL API текущей сборки.
///
/// В обычном запуске значение приходит из нативного flavor'а через
/// [initFlavorConfig]. Web и debug/тесты резолвятся синхронно (same-origin /
/// эмулятор), чтобы не требовать инициализации там, где канала нет.
String get kDefaultApiBaseUrl {
  final cached = _apiBaseUrl;
  if (cached != null) return cached;

  // Web — всегда same-origin, нативного канала нет.
  if (kIsWeb) return _apiBaseUrl = '/api';

  // Отладка/юнит-тесты без инициализации — дефолт на эмулятор.
  if (kDebugMode) return _apiBaseUrl = 'http://10.0.2.2/api';

  // Release-Android: init обязан был отработать в main() до этого обращения.
  throw StateError(
    'initFlavorConfig() должен быть вызван до kDefaultApiBaseUrl '
    '(нативный flavor не инициализирован).',
  );
}

const double kDefaultBatteryThreshold = 20.0;

/// Сколько приложение может пробыть в фоне, прежде чем потребует код доступа.
const Duration kAutoLockTimeout = Duration(minutes: 5);

/// Сколько приложение может простаивать на переднем плане (без действий
/// пользователя), прежде чем заблокируется.
const Duration kIdleLockTimeout = Duration(minutes: 10);

/// Длина цифрового кода быстрого входа.
const int kPinLength = 4;

/// Максимум попыток ввода ПИН до требования входа по паролю.
const int kMaxPinAttempts = 5;
