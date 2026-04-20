import 'package:dio/dio.dart';

import 'constants.dart';
import 'storage.dart';

class ApiClient {
  final StorageService _storage;
  late final Dio _dio;

  /// Callback for force-logout (e.g. when refresh token is invalid).
  void Function()? onForceLogout;

  ApiClient(this._storage) {
    final baseUrl = _storage.customApiUrl ?? kApiBaseUrl;
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));

    _dio.interceptors.add(QueuedInterceptorsWrapper(
      onRequest: (opts, handler) async {
        final token = await _storage.accessToken;
        if (token != null) {
          opts.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(opts);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Try to refresh
          final refreshed = await _tryRefresh();
          if (refreshed) {
            // Retry original request
            final opts = error.requestOptions;
            final token = await _storage.accessToken;
            opts.headers['Authorization'] = 'Bearer $token';
            try {
              final resp = await _dio.fetch(opts);
              return handler.resolve(resp);
            } catch (e) {
              return handler.next(error);
            }
          }
          // Refresh failed → force logout
          onForceLogout?.call();
        }
        handler.next(error);
      },
    ));
  }

  Future<bool> _tryRefresh() async {
    final refresh = await _storage.refreshToken;
    if (refresh == null) return false;
    try {
      final baseUrl = _storage.customApiUrl ?? kApiBaseUrl;
      final resp = await Dio().post(
        '$baseUrl/auth/doctor/refresh',
        data: {'refresh': refresh},
      );
      if (resp.statusCode == 200) {
        await _storage.setAccessToken(resp.data['access']);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ─── Auth ─────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String username, String password) async {
    final resp = await _dio.post('/auth/doctor/login', data: {
      'username': username,
      'password': password,
    });
    return resp.data;
  }

  // ─── Doctor Profile ───────────────────────────────────

  Future<Map<String, dynamic>> getProfile() async {
    final resp = await _dio.get('/doctors/me');
    return resp.data;
  }

  Future<List<dynamic>> listDoctors() async {
    final resp = await _dio.get('/doctors/list');
    return resp.data;
  }

  // ─── Patients ─────────────────────────────────────────

  Future<List<dynamic>> getPatients({String? search}) async {
    final resp = await _dio.get(
      '/doctors/me/patients',
      queryParameters: {if (search != null && search.isNotEmpty) 'search': search},
    );
    return resp.data;
  }

  Future<Map<String, dynamic>> createPatient(
    String username,
    String password, {
    String lastName = '',
    String firstName = '',
    String patronymic = '',
    DateTime? birthDate,
  }) async {
    final resp = await _dio.post('/doctors/patients', data: {
      'username': username,
      'password': password,
      'last_name': lastName,
      'first_name': firstName,
      'patronymic': patronymic,
      if (birthDate != null) 'birth_date': _dateToIso(birthDate),
    });
    return resp.data;
  }

  Future<Map<String, dynamic>> setStartingSound(int patientId, int? audioFileId) async {
    final resp = await _dio.put(
      '/doctors/patients/$patientId/starting-sound',
      data: {'audio_file_id': audioFileId},
    );
    return resp.data;
  }

  Future<Map<String, dynamic>> updatePatient(
    int patientId, {
    String? lastName,
    String? firstName,
    String? patronymic,
    Object? birthDate = _unset,
  }) async {
    final data = <String, dynamic>{};
    if (lastName != null) data['last_name'] = lastName;
    if (firstName != null) data['first_name'] = firstName;
    if (patronymic != null) data['patronymic'] = patronymic;
    if (!identical(birthDate, _unset)) {
      data['birth_date'] = birthDate == null ? null : _dateToIso(birthDate as DateTime);
    }
    final resp = await _dio.patch('/doctors/patients/$patientId', data: data);
    return resp.data;
  }

  Future<Map<String, dynamic>> setBirthDate(int patientId, DateTime? date) =>
      updatePatient(patientId, birthDate: date);

  static String _dateToIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static const _unset = Object();

  Future<Map<String, dynamic>> transferPatient(int patientId, String toDoctorId) async {
    final resp = await _dio.post('/doctors/transfer-patient', data: {
      'patient_id': patientId,
      'to_doctor_id': toDoctorId,
    });
    return resp.data;
  }

  // ─── Results & Assignments ────────────────────────────

  Future<List<dynamic>> getPatientResults(int patientId) async {
    final resp = await _dio.get('/doctors/patients/$patientId/results');
    return resp.data;
  }

  Future<List<dynamic>> getPatientAssignments(int patientId) async {
    final resp = await _dio.get('/doctors/patients/$patientId/assignments');
    return resp.data;
  }

  Future<Map<String, dynamic>> assignQuiz(
    int patientId,
    int quizId, {
    String? startsAt,
    String? endsAt,
  }) async {
    final data = <String, dynamic>{'quiz_id': quizId};
    if (startsAt != null) data['starts_at'] = startsAt;
    if (endsAt != null) data['ends_at'] = endsAt;
    final resp = await _dio.post('/doctors/patients/$patientId/assign-quiz', data: data);
    return resp.data;
  }

  Future<void> unassignQuiz(int patientId, int assignmentId) async {
    await _dio.delete('/doctors/patients/$patientId/assignments/$assignmentId');
  }

  Future<List<dynamic>> getQuizAudio(int quizId) async {
    final resp = await _dio.get('/doctors/quizzes/$quizId/audio');
    return resp.data;
  }

  // ─── Quizzes ──────────────────────────────────────────

  Future<List<dynamic>> listQuizzes() async {
    final resp = await _dio.get('/doctors/quizzes');
    return resp.data;
  }

  // ─── Audio Library ────────────────────────────────────

  Future<List<dynamic>> listAudio({int? categoryId}) async {
    final params = <String, dynamic>{};
    if (categoryId != null) params['category_id'] = categoryId;
    final resp = await _dio.get('/doctors/audio-library', queryParameters: params);
    return resp.data;
  }

  Future<List<dynamic>> listCategories() async {
    final resp = await _dio.get('/doctors/audio-library/categories');
    return resp.data;
  }

  Future<Map<String, dynamic>> createCategory(String name, {int? parentId}) async {
    final resp = await _dio.post('/doctors/audio-library/categories', data: {
      'name': name,
      if (parentId != null) 'parent_id': parentId,
    });
    return resp.data;
  }

  Future<Map<String, dynamic>> renameCategory(int id, String name) async {
    final resp = await _dio.put('/doctors/audio-library/categories/$id', data: {'name': name});
    return resp.data;
  }

  Future<void> deleteCategory(int id) async {
    await _dio.delete('/doctors/audio-library/categories/$id');
  }

  Future<void> moveAudio(int audioId, int categoryId) async {
    await _dio.put('/doctors/audio-library/$audioId/move', data: {'category_id': categoryId});
  }

  // ─── Notifications ────────────────────────────────────

  Future<Map<String, dynamic>> getNotifications({bool unreadOnly = false}) async {
    final resp = await _dio.get('/doctors/notifications', queryParameters: {
      if (unreadOnly) 'unread_only': true,
    });
    return resp.data;
  }

  Future<void> markNotificationRead(int id) async {
    await _dio.post('/doctors/notifications/$id/read');
  }
}
