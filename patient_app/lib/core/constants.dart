/// Flavor передаётся через --dart-define=FLAVOR=dev|prod|android-dev|android-preprod|android-prod
///
/// Конвенция (общая с doctor_app):
///   dev             — локальный запуск (flutter run -d chrome): docker-compose на localhost
///   prod            — деплой на web (Coolify, medear.ru): относительный /api, тот же origin
///   android-dev     — Android-эмулятор: 10.0.2.2 = хост-машина
///   android-preprod — Android APK на preprod-стенде (Coolify): ear.dev.webprods.ru
///   android-prod    — Android APK в проде: абсолютный URL продакшена
const String kFlavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

const Map<String, String> kDefaultApiUrls = {
  'dev': '/api',
  'prod': '/api',
  'android-dev': 'http://10.0.2.2/api',
  'android-preprod': 'https://ear.dev.webprods.ru/api',
  'android-prod': 'https://api.medear.ru/api',
};

String get kDefaultApiBaseUrl => kDefaultApiUrls[kFlavor] ?? kDefaultApiUrls['dev']!;

const double kDefaultBatteryThreshold = 20.0;

/// Сколько приложение может пробыть в фоне, прежде чем потребует код доступа.
const Duration kAutoLockTimeout = Duration(minutes: 5);

/// Длина цифрового кода быстрого входа.
const int kPinLength = 4;

/// Максимум попыток ввода ПИН до требования входа по паролю.
const int kMaxPinAttempts = 5;
