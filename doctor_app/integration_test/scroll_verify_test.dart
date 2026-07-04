// Verifies that the patient detail page scrolls via mouse wheel and PageDown.
// Runs in real Chrome:  flutter test integration_test/scroll_verify_test.dart -d chrome
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:doctor_app/core/api_client.dart';
import 'package:doctor_app/core/storage.dart';
import 'package:doctor_app/providers/auth_provider.dart';
import 'package:doctor_app/screens/patient_detail_screen.dart';

/// Fake API returning enough content to overflow a small window.
class _FakeApi extends ApiClient {
  _FakeApi(StorageService s) : super(s);

  @override
  Future<List<dynamic>> getPatients({String? search}) async => [
        {
          'id': 1,
          'username': 'patient_1',
          'doctor_id': 'd1',
          'full_name': 'Иванов Иван Иванович',
          'starting_sound_id': null,
          'assigned_count': 6,
          'completed_count': 4,
          'created_at': '2026-01-01T00:00:00Z',
        }
      ];

  @override
  Future<List<dynamic>> getPatientAssignments(int patientId) async =>
      List.generate(6, (i) => {
            'id': i + 1,
            'quiz_id': i + 1,
            'quiz_title': 'Тест № ${i + 1}. Проверка слуха',
            'status': 'assigned',
            'assigned_at': '2026-06-01T10:00:00Z',
            'ends_at': '2027-01-01T10:00:00Z',
            'is_expired': false,
          });

  @override
  Future<List<dynamic>> getPatientResults(int patientId) async =>
      List.generate(4, (i) => {
            'assignment_id': 100 + i,
            'quiz_title': 'Пройденный тест № ${i + 1}',
            'answers': const [
              {'question_id': 1, 'answer': 'да'},
              {'question_id': 2, 'answer': 'нет'},
            ],
            'score': 5,
            'submitted_at': '2026-06-10T12:00:00Z',
          });

  @override
  Future<List<dynamic>> listAudio({int? categoryId}) async =>
      List.generate(8, (i) => {
            'id': i + 1,
            'title': 'Звук ${i + 1}',
            'file': 'https://example.com/a$i.mp3',
            'category_id': 1,
            'duration_seconds': 3,
            'uploaded_at': '2026-01-01T00:00:00Z',
          });

  @override
  Future<List<dynamic>> listQuizzes() async => [];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('patient detail scrolls via mouse wheel and PageDown',
      (tester) async {
    // Small window so the content overflows and must scroll.
    tester.view.physicalSize = const Size(760, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final storage = StorageService();
    await storage.init();
    final fake = _FakeApi(storage);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(fake)],
        child: const MaterialApp(
          home: PatientDetailScreen(patientId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Expand the "Стартовый звук" panel to add height below it.
    await tester.tap(find.text('Стартовый звук'));
    await tester.pumpAndSettle();

    // The main ListView's scroll position.
    final scrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    final state = tester.state<ScrollableState>(scrollable);
    double px() => state.position.pixels;

    expect(state.position.maxScrollExtent, greaterThan(0),
        reason: 'content should overflow the viewport');

    // --- 1. Mouse wheel ---
    state.position.jumpTo(0);
    await tester.pump();
    final beforeWheel = px();
    final center = tester.getCenter(scrollable);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 400)));
    await tester.pumpAndSettle();
    final afterWheel = px();
    expect(afterWheel, greaterThan(beforeWheel),
        reason: 'mouse wheel should scroll the page down');

    // --- 2. PageDown (keyboard) ---
    // No manual focus: the page autofocuses a node inside the scroll view on
    // load, so PageDown should scroll immediately.
    state.position.jumpTo(0);
    await tester.pump();
    final beforePageDown = px();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    final afterPageDown = px();
    expect(afterPageDown, greaterThan(beforePageDown),
        reason: 'PageDown should scroll the page down');

    // --- 3. PageUp returns up ---
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(px(), lessThan(afterPageDown),
        reason: 'PageUp should scroll the page up');

    debugPrint('SCROLL OK: max=${state.position.maxScrollExtent} '
        'wheel $beforeWheel->$afterWheel '
        'pageDown $beforePageDown->$afterPageDown');
  });
}
