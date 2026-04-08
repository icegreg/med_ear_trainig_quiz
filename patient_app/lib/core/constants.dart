/// Flavor передаётся через --dart-define=FLAVOR=dev|prod
const String kFlavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

/// Дефолтные URL API по flavor (можно переопределить в настройках приложения)
/// dev: localhost для web/desktop, 10.0.2.2 для Android-эмулятора
const Map<String, String> kDefaultApiUrls = {
  'dev': '/api',
  'android-dev': 'http://10.0.2.2/api',
  'prod': 'https://api.medear.ru/api',
};

String get kDefaultApiBaseUrl => kDefaultApiUrls[kFlavor] ?? kDefaultApiUrls['dev']!;

const double kDefaultBatteryThreshold = 20.0;
const double kDefaultVolume = 0.8;
