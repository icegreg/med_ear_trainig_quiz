// E2E (real Chrome): блок статистики на карточке пациента — приверженность,
// динамика результатов, ошибки по звукам.
//   flutter test integration_test/stats_e2e_test.dart --device-id chrome
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:doctor_app/core/api_client.dart';
import 'package:doctor_app/core/storage.dart';
import 'package:doctor_app/providers/auth_provider.dart';
import 'package:doctor_app/screens/patient_detail_screen.dart';
import 'package:doctor_app/widgets/patient_stats_section.dart';

class _FakeApi extends ApiClient {
  _FakeApi(StorageService s, {required this.stats}) : super(s);

  final Map<String, dynamic> stats;
  int statsCalls = 0;

  @override
  Future<List<dynamic>> getPatients({String? search}) async => [
        {
          'id': 1,
          'username': 'ivanovps',
          'doctor_id': 'd1',
          'full_name': 'Иванов Пётр Сергеевич',
          'starting_sound_id': null,
          'assigned_count': 1,
          'completed_count': 2,
          'unreviewed_count': 0,
          'created_at': '2026-01-01T00:00:00Z',
        }
      ];

  @override
  Future<Map<String, dynamic>> getPatientStats(int patientId) async {
    statsCalls++;
    return stats;
  }

  @override
  Future<int> markResultsViewed(int patientId) async => 0;

  @override
  Future<List<dynamic>> getPatientAssignments(int patientId) async => [];

  @override
  Future<List<dynamic>> getPatientResults(int patientId) async => [];

  @override
  Future<List<dynamic>> listAudio({int? categoryId}) async => [];
}

/// Ответ сервера с двумя пройденными тестами и двумя звуками.
Map<String, dynamic> _statsFixture() => {
      'dynamics': [
        {
          'assignment_id': 1,
          'quiz_title': 'Первый тест',
          'score': 1,
          'total': 2,
          'percent': 50.0,
          'submitted_at': '2026-03-01T10:00:00Z',
        },
        {
          'assignment_id': 2,
          'quiz_title': 'Второй тест',
          'score': 4,
          'total': 4,
          'percent': 100.0,
          'submitted_at': '2026-03-08T10:00:00Z',
        },
      ],
      'sound_errors': [
        {
          'audio_id': 10,
          'title': 'Низкий гул',
          'category': 'Низкие частоты',
          'answered': 4,
          'errors': 3,
          'error_percent': 75.0,
          'is_deleted': false,
        },
        {
          'audio_id': 11,
          'title': 'Старый звук',
          'category': null,
          'answered': 2,
          'errors': 0,
          'error_percent': 0.0,
          'is_deleted': true,
        },
      ],
      'adherence': {
        'assigned': 1,
        'completed': 2,
        'expired': 1,
        'upcoming': 0,
        'completion_lag_days': [3, 5],
        'avg_completion_days': 4.0,
      },
    };

Map<String, dynamic> _emptyStats() => {
      'dynamics': [],
      'sound_errors': [],
      'adherence': {
        'assigned': 0,
        'completed': 0,
        'expired': 0,
        'upcoming': 0,
        'completion_lag_days': [],
        'avg_completion_days': null,
      },
    };

Future<void> _pumpFor(WidgetTester t, [int ms = 1200]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(_FakeApi fake, Widget home) => ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(fake)],
      child: MaterialApp(home: home),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  setUpAll(() async {
    storage = StorageService();
    await storage.init();
  });

  testWidgets('stats section renders adherence, dynamics and sound errors',
      (tester) async {
    final fake = _FakeApi(storage, stats: _statsFixture());
    await tester.pumpWidget(_app(
      fake,
      const Scaffold(body: PatientStatsSection(patientId: 1)),
    ));
    await _pumpFor(tester);

    expect(fake.statsCalls, 1);

    // Приверженность: плитки + средний лаг.
    expect(find.byKey(const Key('stats_adherence')), findsOneWidget);
    expect(find.text('Пройдено'), findsOneWidget);
    expect(find.text('Просрочено'), findsOneWidget);
    expect(find.textContaining('В среднем проходит за 4 дня'), findsOneWidget);

    // Динамика: две точки → рисуется график, а не hero-число.
    expect(find.byKey(const Key('stats_dynamics')), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);

    // Ошибки по звукам: подписи значений прямо на барах.
    expect(find.byKey(const Key('stats_sound_errors')), findsOneWidget);
    expect(find.textContaining('Низкий гул'), findsOneWidget);
    expect(find.textContaining('75%  (3 из 4)'), findsOneWidget);
    // Удалённый звук не исчезает из агрегата, а помечается.
    expect(find.textContaining('Старый звук (удалён)'), findsOneWidget);

    debugPrint('E2E patient stats OK');
  });

  testWidgets('single result renders a hero number instead of a chart',
      (tester) async {
    final stats = _statsFixture();
    stats['dynamics'] = [stats['dynamics'][0]];
    final fake = _FakeApi(storage, stats: stats);
    await tester.pumpWidget(_app(
      fake,
      const Scaffold(body: PatientStatsSection(patientId: 1)),
    ));
    await _pumpFor(tester);

    expect(find.byType(LineChart), findsNothing);
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('Первый тест'), findsOneWidget);

    debugPrint('E2E single-point hero number OK');
  });

  testWidgets('patient without results shows empty states, not errors',
      (tester) async {
    final fake = _FakeApi(storage, stats: _emptyStats());
    await tester.pumpWidget(_app(
      fake,
      const Scaffold(body: PatientStatsSection(patientId: 1)),
    ));
    await _pumpFor(tester);

    expect(find.text('Пациент ещё не прошёл ни одного теста'), findsOneWidget);
    expect(find.textContaining('Нет данных'), findsWidgets);
    expect(find.textContaining('Ошибка'), findsNothing);

    debugPrint('E2E empty stats OK');
  });

  testWidgets('patient card shows the stats block', (tester) async {
    final fake = _FakeApi(storage, stats: _statsFixture());
    await tester.pumpWidget(_app(
      fake,
      const PatientDetailScreen(patientId: 1),
    ));
    await _pumpFor(tester);

    expect(find.text('Статистика'), findsOneWidget);
    expect(find.byKey(const Key('stats_adherence')), findsOneWidget);
    expect(fake.statsCalls, 1);

    debugPrint('E2E stats on patient card OK');
  });
}
