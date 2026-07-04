// E2E (real Chrome) для генерации кредов пациента и сброса пароля.
//   Headless: flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/credentials_e2e_test.dart -d web-server \
//     --browser-name=chrome --headless
//   Headed (нужен дисплей): убрать флаг --headless.
// См. scripts/run_e2e.sh — обёртка с E2E_HEADLESS.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:doctor_app/core/api_client.dart';
import 'package:doctor_app/core/storage.dart';
import 'package:doctor_app/providers/auth_provider.dart';
import 'package:doctor_app/screens/add_patient_screen.dart';
import 'package:doctor_app/screens/patient_detail_screen.dart';

/// Fake API: имитирует бэковую генерацию логина и создание/сброс.
class _FakeApi extends ApiClient {
  _FakeApi(StorageService s) : super(s);

  int resetCalls = 0;
  String? lastCreatedPassword;
  String? lastResetPassword;

  @override
  Future<String> suggestLogin({
    String lastName = '',
    String firstName = '',
    String patronymic = '',
    DateTime? birthDate,
  }) async {
    // Тот же формат, что и на бэке: транслит фамилии + инициалы.
    final map = {'Иванов': 'ivanov', 'Петров': 'petrov'};
    final base = (map[lastName] ?? lastName.toLowerCase());
    final fi = firstName.isNotEmpty ? _translit(firstName[0]) : '';
    final pi = patronymic.isNotEmpty ? _translit(patronymic[0]) : '';
    return '$base$fi$pi';
  }

  static String _translit(String ch) {
    const m = {'П': 'p', 'С': 's', 'И': 'i', 'А': 'a'};
    return m[ch] ?? ch.toLowerCase();
  }

  @override
  Future<Map<String, dynamic>> createPatient(
    String username,
    String password, {
    String lastName = '',
    String firstName = '',
    String patronymic = '',
    DateTime? birthDate,
  }) async {
    lastCreatedPassword = password;
    return {'id': 1, 'username': username};
  }

  @override
  Future<Map<String, dynamic>> resetPassword(
      int patientId, String newPassword) async {
    resetCalls++;
    lastResetPassword = newPassword;
    return {'id': patientId, 'username': 'ivanovps'};
  }

  @override
  Future<Map<String, dynamic>> getProfile() async => {
        'id': 'd1',
        'last_name': 'Петров',
        'first_name': 'Иван',
        'patronymic': 'Сергеевич',
        'clinic': 'Клиника №1',
      };

  @override
  Future<List<dynamic>> getPatients({String? search}) async => [
        {
          'id': 1,
          'username': 'ivanovps',
          'doctor_id': 'd1',
          'full_name': 'Иванов Пётр Сергеевич',
          'starting_sound_id': null,
          'assigned_count': 0,
          'completed_count': 0,
          'created_at': '2026-01-01T00:00:00Z',
        }
      ];

  @override
  Future<List<dynamic>> getPatientAssignments(int patientId) async => [];

  @override
  Future<List<dynamic>> getPatientResults(int patientId) async => [];

  @override
  Future<List<dynamic>> listAudio({int? categoryId}) async => [];
}

Widget _harness(_FakeApi fake, Widget child, {bool withRouter = false}) {
  final overrides = [apiClientProvider.overrideWithValue(fake)];
  if (withRouter) {
    final router = GoRouter(
      initialLocation: '/add',
      routes: [
        GoRoute(path: '/add', builder: (_, __) => child),
        GoRoute(
          path: '/patients/:id',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('patient detail stub'))),
        ),
      ],
    );
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: router),
    );
  }
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

/// Bounded pumping — не используем pumpAndSettle, т.к. мигающий курсор в
/// сфокусированном TextField бесконечно планирует кадры и settle зависает.
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

  testWidgets('create patient: generated login + password, creds card, PDF',
      (tester) async {
    final fake = _FakeApi(storage);
    await tester.pumpWidget(_harness(fake, const AddPatientScreen(),
        withRouter: true));
    await _pumpFor(tester);

    // Пароль сгенерирован сразу.
    final pwField =
        tester.widget<TextField>(find.byKey(const Key('field_password')));
    expect(pwField.controller!.text.length, 12);
    expect(RegExp(r'^[A-Za-z0-9]{12}$').hasMatch(pwField.controller!.text),
        isTrue);
    final password = pwField.controller!.text;

    // Ввод ФИО → автогенерация логина (debounce 500ms).
    await tester.enterText(find.byKey(const Key('field_last_name')), 'Иванов');
    await tester.enterText(find.byKey(const Key('field_first_name')), 'Пётр');
    await tester.enterText(
        find.byKey(const Key('field_patronymic')), 'Сергеевич');
    await tester.pump(const Duration(milliseconds: 700));
    await _pumpFor(tester);

    final loginField =
        tester.widget<TextField>(find.byKey(const Key('field_login')));
    expect(loginField.controller!.text, 'ivanovps');

    // Создание → карточка кредов.
    await tester.tap(find.byKey(const Key('btn_create')));
    await _pumpFor(tester);

    expect(fake.lastCreatedPassword, password);
    final shownLogin =
        tester.widget<SelectableText>(find.byKey(const Key('creds_login'))).data;
    final shownPw = tester
        .widget<SelectableText>(find.byKey(const Key('creds_password')))
        .data;
    expect(shownLogin, 'ivanovps');
    expect(shownPw, password);

    // Готово → навигация на карточку пациента.
    await tester.tap(find.byKey(const Key('creds_done')));
    await _pumpFor(tester);
    expect(find.text('patient detail stub'), findsOneWidget);

    debugPrint('E2E create OK: login=ivanovps password_len=${password.length}');
  });

  testWidgets('reset password: creds card with new password + PDF',
      (tester) async {
    final fake = _FakeApi(storage);
    await tester.pumpWidget(
        _harness(fake, const PatientDetailScreen(patientId: 1)));
    await _pumpFor(tester);

    await tester.tap(find.byKey(const Key('btn_reset_password')));
    await _pumpFor(tester);
    await tester.tap(find.byKey(const Key('confirm_reset_password')));
    await _pumpFor(tester);

    expect(fake.resetCalls, 1);
    expect(find.text('Пароль сброшен'), findsOneWidget);
    final shownPw = tester
        .widget<SelectableText>(find.byKey(const Key('creds_password')))
        .data;
    expect(shownPw, fake.lastResetPassword);
    expect(shownPw!.length, 12);

    await tester.tap(find.byKey(const Key('creds_done')));
    await _pumpFor(tester);

    debugPrint('E2E reset OK: password_len=${shownPw.length}');
  });
}
