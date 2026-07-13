// E2E (real Chrome): по-вопросный разбор пройденного теста на карточке пациента.
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/result_breakdown_e2e_test.dart -d web-server \
//     --browser-name=chrome --headless
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:doctor_app/core/api_client.dart';
import 'package:doctor_app/core/storage.dart';
import 'package:doctor_app/providers/auth_provider.dart';
import 'package:doctor_app/screens/patient_detail_screen.dart';
import 'package:doctor_app/widgets/result_breakdown_view.dart';

class _FakeApi extends ApiClient {
  _FakeApi(StorageService s) : super(s);

  int breakdownCalls = 0;

  @override
  Future<List<dynamic>> getPatients({String? search}) async => [
        {
          'id': 1,
          'username': 'ivanovps',
          'doctor_id': 'd1',
          'full_name': 'Иванов Пётр Сергеевич',
          'starting_sound_id': null,
          'assigned_count': 0,
          'completed_count': 1,
          'unreviewed_count': 0,
          'created_at': '2026-01-01T00:00:00Z',
        }
      ];

  @override
  Future<List<dynamic>> getPatientResults(int patientId) async => [
        {
          'assignment_id': 77,
          'quiz_title': 'Проверка слуха',
          'answers': [],
          'score': 1,
          'submitted_at': '2026-03-01T10:00:00Z',
        }
      ];

  @override
  Future<Map<String, dynamic>> getResultBreakdown(int assignmentId) async {
    breakdownCalls++;
    return {
      'assignment_id': assignmentId,
      'quiz_title': 'Проверка слуха',
      'submitted_at': '2026-03-01T10:00:00Z',
      'score': 1,
      'total': 3,
      'percent': 33.3,
      'questions': [
        {
          'question_id': 1,
          'order': 1,
          'text': 'Слышите гул?',
          'audio_id': 10,
          'audio_title': 'Гул 500 Гц',
          'audio_url': '/media/audio/gul.wav',
          'audio_is_deleted': false,
          'patient_answer': 'нет',
          'correct_answer': 'да',
          'is_correct': false,
          'question_deleted': false,
        },
        {
          'question_id': 2,
          'order': 2,
          'text': 'Слышите свист?',
          'audio_id': 11,
          'audio_title': 'Свист 4000 Гц',
          'audio_url': '/media/audio/svist.wav',
          'audio_is_deleted': true,
          'patient_answer': 'да',
          'correct_answer': 'да',
          'is_correct': true,
          'question_deleted': false,
        },
        {
          'question_id': 3,
          'order': 1000000,
          'text': 'Вопрос удалён из теста',
          'audio_id': null,
          'audio_title': null,
          'audio_url': null,
          'audio_is_deleted': false,
          'patient_answer': 'нет',
          'correct_answer': null,
          'is_correct': null,
          'question_deleted': true,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getPatientStats(int patientId) async => {
        'dynamics': [],
        'sound_errors': [],
        'adherence': {
          'assigned': 0,
          'completed': 1,
          'expired': 0,
          'upcoming': 0,
          'completion_lag_days': [],
          'avg_completion_days': null,
        },
      };

  @override
  Future<int> markResultsViewed(int patientId) async => 0;

  @override
  Future<List<dynamic>> getPatientAssignments(int patientId) async => [];

  @override
  Future<List<dynamic>> listAudio({int? categoryId}) async => [];
}

Future<void> _pumpFor(WidgetTester t, [int ms = 1200]) async {
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

  testWidgets('breakdown renders answers, correct answers and deleted markers',
      (tester) async {
    final fake = _FakeApi(storage);
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(fake)],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResultBreakdownView(assignmentId: 77),
          ),
        ),
      ),
    ));
    await _pumpFor(tester);

    expect(fake.breakdownCalls, 1);
    expect(find.byKey(const Key('result_breakdown')), findsOneWidget);

    // Ошибка: показываем и ответ пациента, и правильный ответ.
    expect(find.text('Гул 500 Гц'), findsOneWidget);
    expect(find.text('Слышите гул?'), findsOneWidget);
    expect(find.text('Верно: Слышу'), findsOneWidget);
    // «Не слышу» ответил и на первый вопрос, и на удалённый.
    expect(find.text('Ответ: Не слышу'), findsNWidgets(2));

    // Верный ответ: правильный ответ не дублируем — это был бы шум.
    expect(find.text('Ответ: Слышу'), findsOneWidget);
    expect(find.text('Верно: Не слышу'), findsNothing);

    // Удалённый звук остаётся в разборе, но помечен.
    expect(find.text('Свист 4000 Гц (удалён)'), findsOneWidget);

    // Удалённый вопрос: ответ сохранён, сверять не с чем.
    expect(find.textContaining('Вопрос удалён — сверить не с чем'),
        findsOneWidget);

    debugPrint('E2E result breakdown OK');
  });

  testWidgets('breakdown is loaded lazily — only when the result is expanded',
      (tester) async {
    final fake = _FakeApi(storage);
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: PatientDetailScreen(patientId: 1)),
    ));
    await _pumpFor(tester);

    // Карточка открыта, результат свёрнут — разбор ещё не запрошен.
    expect(fake.breakdownCalls, 0);
    expect(find.byKey(const Key('result_breakdown')), findsNothing);

    // Результаты — внизу страницы, ListView строит их лениво: доскроллим.
    await tester.scrollUntilVisible(
      find.text('Проверка слуха'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await _pumpFor(tester);

    await tester.tap(find.text('Проверка слуха'));
    await _pumpFor(tester);

    expect(fake.breakdownCalls, 1);
    expect(find.text('Слышите гул?'), findsOneWidget);

    debugPrint('E2E lazy breakdown OK');
  });
}
