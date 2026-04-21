/// Flavor передаётся через --dart-define=FLAVOR=dev|prod|android-dev|android-prod
///
/// Конвенция (общая с patient_app):
///   dev          — локальный запуск (flutter run -d chrome): docker-compose на localhost
///   prod         — деплой на web (Coolify, medear.ru): относительный /api, тот же origin
///   android-dev  — Android-эмулятор: 10.0.2.2 = хост-машина
///   android-prod — Android APK в проде: абсолютный URL продакшена
const String kFlavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

const Map<String, String> kDefaultApiUrls = {
  'dev': '/api',
  'prod': '/api',
  'android-dev': 'http://10.0.2.2/api',
  'android-prod': 'https://api.medear.ru/api',
};

String get kApiBaseUrl => kDefaultApiUrls[kFlavor] ?? kDefaultApiUrls['dev']!;
