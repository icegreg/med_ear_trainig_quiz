// E2E (real Chrome): статус «непроверенные тесты» — бейдж в списке и
// автоотметка просмотра при открытии карточки пациента.
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/unreviewed_e2e_test.dart -d web-server \
//     --browser-name=chrome --headless
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:doctor_app/core/api_client.dart';
import 'package:doctor_app/core/storage.dart';
import 'package:doctor_app/providers/auth_provider.dart';
import 'package:doctor_app/screens/patient_detail_screen.dart';
import 'package:doctor_app/screens/patients_list_screen.dart';

class _FakeApi extends ApiClient {
  _FakeApi(StorageService s) : super(s);

  int markViewedCalls = 0;
  int unreviewed = 2;

  @override
  Future<List<dynamic>> getPatients({String? search}) async => [
        {
          'id': 1,
          'username': 'ivanovps',
          'doctor_id': 'd1',
          'full_name': 'Иванов Пётр Сергеевич',
          'starting_sound_id': null,
          'assigned_count': 1,
          'completed_count': 3,
          'unreviewed_count': unreviewed,
          'created_at': '2026-01-01T00:00:00Z',
        }
      ];

  @override
  Future<int> markResultsViewed(int patientId) async {
    markViewedCalls++;
    unreviewed = 0; // после просмотра — обнуляем
    return 2;
  }

  @override
  Future<List<dynamic>> getPatientAssignments(int patientId) async => [];

  @override
  Future<List<dynamic>> getPatientResults(int patientId) async => [];

  @override
  Future<List<dynamic>> listAudio({int? categoryId}) async => [];
}

Future<void> _pumpFor(WidgetTester t, [int ms = 800]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  setUpAll(() async {
    storage = StorageService();
    await storage.init();
  });

  testWidgets('patients list shows unreviewed badge', (tester) async {
    final fake = _FakeApi(storage);
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: PatientsListScreen()),
    ));
    await _pumpFor(tester);

    expect(find.textContaining('Непроверенных: 2'), findsOneWidget);
    debugPrint('E2E unreviewed badge OK');
  });

  testWidgets('opening patient card auto-marks results viewed',
      (tester) async {
    final fake = _FakeApi(storage);
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: PatientDetailScreen(patientId: 1)),
    ));
    await _pumpFor(tester);

    expect(fake.markViewedCalls, 1);
    expect(fake.unreviewed, 0);
    debugPrint('E2E auto-mark viewed OK');
  });
}
