import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/core/constants.dart';

/// Проверяет плуминг выбора API-хоста.
///
/// Реальный хост каждого окружения теперь живёт в нативном product flavor
/// (Gradle buildConfigField API_BASE_URL) и отдаётся в Dart через MethodChannel
/// com.medear.patient_app/config. Здесь мы мокаем этот канал и убеждаемся, что
/// initFlavorConfig() поднимает пришедший хост, а kDefaultApiBaseUrl его отдаёт.
///
/// Физическую привязку flavor→хост (в каждом APK только свой адрес) проверяем
/// сборкой APK и grep'ом по dex, не unit-тестом.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.medear.patient_app/config');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('initFlavorConfig берёт API-хост из нативного flavor-канала', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApiBaseUrl') return 'https://api.medear.ru/api';
      return null;
    });

    await initFlavorConfig();

    expect(kDefaultApiBaseUrl, 'https://api.medear.ru/api');
    expect(kDefaultApiBaseUrl, isNot(contains('webprods')));
    expect(kDefaultApiBaseUrl, isNot(contains('10.0.2.2')));
  });
}
