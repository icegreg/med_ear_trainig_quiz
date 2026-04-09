import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// E2E-тесты приложения пациента с реальным сервером.
/// Сервер должен быть запущен: docker compose up
///
/// Запуск: flutter test test/api_integration_test.dart

const baseUrl = 'http://localhost/api';
const mediaBaseUrl = 'http://localhost';

void main() {
  late Dio dio;
  late String deviceToken;
  late int patientId;

  Dio authedDio() => Dio(BaseOptions(
        baseUrl: baseUrl,
        headers: {'Authorization': 'Bearer $deviceToken'},
        validateStatus: (s) => s != null && s < 500,
      ));

  Dio authedMediaDio() => Dio(BaseOptions(
        baseUrl: mediaBaseUrl,
        headers: {'Authorization': 'Bearer $deviceToken'},
        validateStatus: (s) => s != null && s < 500,
      ));

  setUpAll(() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      validateStatus: (status) => status != null && status < 500,
    ));
  });

  tearDownAll(() => dio.close());

  // ============================================================
  // 1. AUTH
  // ============================================================

  group('1. Auth', () {
    test('неверные данные → 401', () async {
      final resp = await dio.post('/auth/device-token', data: {
        'username': 'wrong',
        'password': 'wrong',
      });
      expect(resp.statusCode, 401);
    });

    test('успешный логин → device token', () async {
      final resp = await dio.post('/auth/device-token', data: {
        'username': 'testpatient',
        'password': 'patpass123',
        'device_info': 'flutter-e2e-test',
      });
      expect(resp.statusCode, 200);
      expect(resp.data['token'], isNotEmpty);
      expect(resp.data['patient_id'], isA<int>());

      deviceToken = resp.data['token'];
      patientId = resp.data['patient_id'];
    });
  });

  // ============================================================
  // 2. ЗАЩИТА ЭНДПОИНТОВ — без токена
  // ============================================================

  group('2. Защита без токена', () {
    test('GET /patients/me → 401', () async {
      final resp = await dio.get('/patients/me');
      expect(resp.statusCode, 401);
    });

    test('GET /patients/me/quizzes → 401', () async {
      final resp = await dio.get('/patients/me/quizzes');
      expect(resp.statusCode, 401);
    });

    test('GET /patients/me/results → 401', () async {
      final resp = await dio.get('/patients/me/results');
      expect(resp.statusCode, 401);
    });

    test('GET /quizzes/1 → 401', () async {
      final resp = await dio.get('/quizzes/1');
      expect(resp.statusCode, 401);
    });

    test('GET /quizzes/1/audio → 401', () async {
      final resp = await dio.get('/quizzes/1/audio');
      expect(resp.statusCode, 401);
    });

    test('POST /quizzes/1/submit → 401', () async {
      final resp = await dio.post('/quizzes/1/submit',
          data: {'answers': []});
      expect(resp.statusCode, 401);
    });

    test('GET /media/audio/test.wav → 403', () async {
      final mediaDio = Dio(BaseOptions(
        baseUrl: mediaBaseUrl,
        validateStatus: (s) => s != null && s < 500,
      ));
      final resp = await mediaDio.get('/media/audio/tone1k.wav');
      expect(resp.statusCode, 403);
    });
  });

  // ============================================================
  // 3. ПРОФИЛЬ ПАЦИЕНТА
  // ============================================================

  group('3. Профиль пациента', () {
    test('GET /patients/me → данные профиля', () async {
      final resp = await authedDio().get('/patients/me');
      expect(resp.statusCode, 200);
      expect(resp.data['username'], 'testpatient');
      expect(resp.data['id'], patientId);
      expect(resp.data['doctor_id'], isNotNull);
    });
  });

  // ============================================================
  // 4. СПИСОК ТЕСТОВ
  // ============================================================

  group('4. Список тестов', () {
    test('GET /patients/me/quizzes → есть назначенные', () async {
      final resp = await authedDio().get('/patients/me/quizzes');
      expect(resp.statusCode, 200);
      expect(resp.data, isA<List>());
      expect(resp.data.length, greaterThanOrEqualTo(1));

      final quiz = resp.data[0];
      expect(quiz['id'], isA<int>());
      expect(quiz['title'], isNotEmpty);
      expect(quiz['status'], 'assigned');
      expect(quiz['assigned_at'], isNotEmpty);
    });

    test('GET /patients/me/results → пусто до прохождения', () async {
      final resp = await authedDio().get('/patients/me/results');
      expect(resp.statusCode, 200);
      expect(resp.data, isEmpty);
    });
  });

  // ============================================================
  // 5. ДЕТАЛИ КВИЗА И АУДИО
  // ============================================================

  group('5. Детали квиза и аудио', () {
    late int quizId;

    test('получить ID назначенного теста', () async {
      final resp = await authedDio().get('/patients/me/quizzes');
      final assigned =
          (resp.data as List).where((q) => q['status'] == 'assigned').toList();
      expect(assigned, isNotEmpty);
      quizId = assigned.first['id'];
    });

    test('GET /quizzes/{id} → вопросы с вариантами', () async {
      final resp = await authedDio().get('/quizzes/$quizId');
      expect(resp.statusCode, 200);
      expect(resp.data['title'], isNotEmpty);
      expect(resp.data['questions'], isA<List>());

      final questions = resp.data['questions'] as List;
      expect(questions.length, greaterThan(0));

      final q = questions[0];
      expect(q['id'], isA<int>());
      expect(q['text'], isNotEmpty);
      expect(q['options'], isA<List>());
      expect(q['options'], contains('да'));
      expect(q['options'], contains('нет'));
      expect(q['order'], isA<int>());
    });

    test('GET /quizzes/{id}/audio → файлы с URL', () async {
      final resp = await authedDio().get('/quizzes/$quizId/audio');
      expect(resp.statusCode, 200);
      expect(resp.data, isA<List>());
      expect(resp.data.length, greaterThan(0));

      final audio = resp.data[0];
      expect(audio['id'], isA<int>());
      expect(audio['title'], isNotEmpty);
      expect(audio['file'], isNotEmpty);
    });

    test('скачивание аудио-файла с токеном → 200', () async {
      final audioResp = await authedDio().get('/quizzes/$quizId/audio');
      final fileUrl = audioResp.data[0]['file'] as String;

      final resp = await authedMediaDio().get(fileUrl);
      expect(resp.statusCode, 200);
    });

    test('скачивание аудио-файла без токена → 403', () async {
      final audioResp = await authedDio().get('/quizzes/$quizId/audio');
      final fileUrl = audioResp.data[0]['file'] as String;

      final noAuthDio = Dio(BaseOptions(
        baseUrl: mediaBaseUrl,
        validateStatus: (s) => s != null && s < 500,
      ));
      final resp = await noAuthDio.get(fileUrl);
      expect(resp.statusCode, 403);
    });
  });

  // ============================================================
  // 6. ПРОХОЖДЕНИЕ ТЕСТА (SUBMIT)
  // ============================================================

  group('6. Прохождение теста', () {
    late int quizId;
    late List<dynamic> questions;

    test('загрузить вопросы', () async {
      final listResp = await authedDio().get('/patients/me/quizzes');
      quizId = (listResp.data as List)
          .firstWhere((q) => q['status'] == 'assigned')['id'];

      final detail = await authedDio().get('/quizzes/$quizId');
      questions = detail.data['questions'];
      expect(questions.length, 3);
    });

    test('POST /quizzes/{id}/submit — все ответы «да» → ok + score', () async {
      final answers = questions
          .map((q) => {'question_id': q['id'], 'answer': 'да'})
          .toList();

      final resp = await authedDio()
          .post('/quizzes/$quizId/submit', data: {'answers': answers});
      expect(resp.statusCode, 200);
      expect(resp.data['status'], 'ok');
      expect(resp.data['message'], contains('успешно'));
    });

    test('повторная отправка → 403', () async {
      final resp = await authedDio()
          .post('/quizzes/$quizId/submit', data: {'answers': []});
      expect(resp.statusCode, 403);
    });
  });

  // ============================================================
  // 7. РЕЗУЛЬТАТЫ ПОСЛЕ ПРОХОЖДЕНИЯ
  // ============================================================

  group('7. Результаты', () {
    test('GET /patients/me/results → появился результат', () async {
      final resp = await authedDio().get('/patients/me/results');
      expect(resp.statusCode, 200);
      expect(resp.data, isA<List>());
      expect(resp.data.length, greaterThan(0));

      final result = resp.data[0];
      expect(result['quiz_title'], isNotEmpty);
      expect(result['score'], isA<int>());
      expect(result['score'], greaterThan(0));
      expect(result['submitted_at'], isNotEmpty);
      expect(result['answers'], isA<List>());
      expect(result['answers'].length, 3);
    });

    test('GET /patients/me/quizzes → статус completed', () async {
      final resp = await authedDio().get('/patients/me/quizzes');
      final quizzes = resp.data as List;
      expect(quizzes.every((q) => q['status'] == 'completed'), isTrue);
    });
  });

  // ============================================================
  // 8. EDGE CASES
  // ============================================================

  group('8. Edge cases', () {
    test('GET /quizzes/99999 → 404 (несуществующий квиз)', () async {
      final resp = await authedDio().get('/quizzes/99999');
      expect(resp.statusCode, 404);
    });

    test('POST /quizzes/99999/submit → 404', () async {
      final resp = await authedDio()
          .post('/quizzes/99999/submit', data: {'answers': []});
      expect(resp.statusCode, 404);
    });

    test('media path traversal → blocked', () async {
      // Nginx нормализует ".." — запрос не дойдёт до Django media view
      // Через Django напрямую это 404, через nginx — redirect к другому location
      final resp =
          await authedMediaDio().get('/media/../config/settings.py');
      // Не должен вернуть реальный файл settings.py (content-type != python)
      expect(resp.headers.value('content-type'), isNot(contains('python')));
    });

    test('невалидный device token → 401', () async {
      final badDio = Dio(BaseOptions(
        baseUrl: baseUrl,
        headers: {'Authorization': 'Bearer fake-token-12345'},
        validateStatus: (s) => s != null && s < 500,
      ));
      final resp = await badDio.get('/patients/me');
      expect(resp.statusCode, 401);
    });
  });
}
