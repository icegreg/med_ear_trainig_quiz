/// E2E API integration tests for Doctor App endpoints.
/// Requires a running backend server at localhost:8000.
///
/// Run: flutter test test/api_integration_test.dart
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseUrl = 'http://localhost:8000/api';
const _doctorUsername = 'testdoctor';
const _doctorPassword = 'docpass123';

late Dio _dio;
late String _accessToken;

void main() {
  setUpAll(() {
    _dio = Dio(BaseOptions(baseUrl: _baseUrl));
  });

  group('Auth', () {
    test('wrong credentials returns 401', () async {
      final resp = await _dio.post(
        '/auth/doctor/login',
        data: {'username': 'wrong', 'password': 'wrong'},
        options: Options(validateStatus: (_) => true),
      );
      expect(resp.statusCode, 401);
    });

    test('successful login returns tokens', () async {
      final resp = await _dio.post('/auth/doctor/login', data: {
        'username': _doctorUsername,
        'password': _doctorPassword,
      });
      expect(resp.statusCode, 200);
      expect(resp.data['access'], isNotNull);
      expect(resp.data['refresh'], isNotNull);
      _accessToken = resp.data['access'];
    });
  });

  group('Protected endpoints require auth', () {
    test('GET /doctors/me without token returns 401', () async {
      final resp = await _dio.get(
        '/doctors/me',
        options: Options(validateStatus: (_) => true),
      );
      expect(resp.statusCode, 401);
    });
  });

  group('Doctor Profile', () {
    test('GET /doctors/me', () async {
      final resp = await _dio.get(
        '/doctors/me',
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
      expect(resp.data['first_name'], isNotEmpty);
    });
  });

  group('Patients', () {
    test('GET /doctors/me/patients', () async {
      final resp = await _dio.get(
        '/doctors/me/patients',
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
      expect(resp.data, isList);
    });

    late int createdPatientId;

    test('POST /doctors/patients — create patient', () async {
      final resp = await _dio.post(
        '/doctors/patients',
        data: {'username': 'e2e_patient_${DateTime.now().millisecondsSinceEpoch}', 'password': 'pass123'},
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
      expect(resp.data['id'], isNotNull);
      createdPatientId = resp.data['id'];
    });

    test('POST /doctors/patients — duplicate username returns 400', () async {
      final resp = await _dio.post(
        '/doctors/patients',
        data: {'username': _doctorUsername, 'password': 'pass'},
        options: Options(
          headers: {'Authorization': 'Bearer $_accessToken'},
          validateStatus: (_) => true,
        ),
      );
      expect(resp.statusCode, 400);
    });

    test('GET /doctors/patients/{id}/assignments', () async {
      final resp = await _dio.get(
        '/doctors/patients/$createdPatientId/assignments',
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
      expect(resp.data, isList);
    });

    test('PATCH /doctors/patients/{id} — set birth_date', () async {
      final resp = await _dio.patch(
        '/doctors/patients/$createdPatientId',
        data: {'birth_date': '1988-07-21'},
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
      expect(resp.data['birth_date'], '1988-07-21');
    });
  });

  group('Audio Library', () {
    test('GET /doctors/audio-library', () async {
      final resp = await _dio.get(
        '/doctors/audio-library',
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
      expect(resp.data, isList);
    });

    test('GET /doctors/audio-library/categories', () async {
      final resp = await _dio.get(
        '/doctors/audio-library/categories',
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
      expect(resp.data, isList);
    });

    late int createdCatId;

    test('POST /doctors/audio-library/categories — create', () async {
      final resp = await _dio.post(
        '/doctors/audio-library/categories',
        data: {'name': 'E2E Test Category'},
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
      createdCatId = resp.data['id'];
    });

    test('PUT /doctors/audio-library/categories/{id} — rename', () async {
      final resp = await _dio.put(
        '/doctors/audio-library/categories/$createdCatId',
        data: {'name': 'E2E Renamed'},
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
      expect(resp.data['name'], 'E2E Renamed');
    });

    test('DELETE /doctors/audio-library/categories/{id}', () async {
      final resp = await _dio.delete(
        '/doctors/audio-library/categories/$createdCatId',
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
    });
  });

  group('Quizzes', () {
    test('GET /doctors/quizzes', () async {
      final resp = await _dio.get(
        '/doctors/quizzes',
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
      expect(resp.data, isList);
    });
  });

  group('Notifications', () {
    test('GET /doctors/notifications', () async {
      final resp = await _dio.get(
        '/doctors/notifications',
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
      expect(resp.data['notifications'], isList);
      expect(resp.data['unread_count'], isA<int>());
    });
  });

  group('Doctors list', () {
    test('GET /doctors/list', () async {
      final resp = await _dio.get(
        '/doctors/list',
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      expect(resp.statusCode, 200);
      expect(resp.data, isList);
    });
  });
}
