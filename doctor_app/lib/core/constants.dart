/// Flavor приложения (dev / prod).
const String kFlavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

/// Базовые URL API для каждого окружения.
const Map<String, String> kDefaultApiUrls = {
  'dev': 'http://localhost/api',
  'prod': '/api',
};

/// Текущий API URL.
String get kApiBaseUrl => kDefaultApiUrls[kFlavor] ?? kDefaultApiUrls['dev']!;
