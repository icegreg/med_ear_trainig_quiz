import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import 'storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(storageProvider);
  return ApiClient(storage, ref);
});

class ApiClient {
  final StorageService _storage;
  final Ref _ref;
  late final Dio _dio;

  ApiClient(this._storage, this._ref) {
    _dio = Dio(BaseOptions(
      baseUrl: _storage.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _storage.deviceToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          // Не сбрасываем на auth-эндпоинтах (логин/рефреш)
          final path = error.requestOptions.path;
          if (!path.startsWith('/auth/')) {
            _ref.read(authProvider.notifier).forceLogout();
          }
        }
        handler.next(error);
      },
    ));
  }

  /// Обновить baseUrl (после изменения в настройках)
  void updateBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }

  Dio get dio => _dio;

  // Auth
  Future<Map<String, dynamic>> obtainDeviceToken({
    required String username,
    required String password,
    String deviceInfo = '',
  }) async {
    final response = await _dio.post('/auth/device-token', data: {
      'username': username,
      'password': password,
      'device_info': deviceInfo,
    });
    return response.data;
  }

  // Patient
  Future<Map<String, dynamic>> getMyProfile() async {
    final response = await _dio.get('/patients/me');
    return response.data;
  }

  Future<List<dynamic>> getMyQuizzes() async {
    final response = await _dio.get('/patients/me/quizzes');
    return response.data;
  }

  Future<List<dynamic>> getMyResults() async {
    final response = await _dio.get('/patients/me/results');
    return response.data;
  }

  // Quizzes
  Future<Map<String, dynamic>> getQuizDetail(int quizId) async {
    final response = await _dio.get('/quizzes/$quizId');
    return response.data;
  }

  Future<List<dynamic>> getQuizAudio(int quizId) async {
    final response = await _dio.get('/quizzes/$quizId/audio');
    return response.data;
  }

  /// Скачать аудио-файл в bytes (с авторизацией).
  /// [fileUrl] — относительный или абсолютный URL из AudioFile.file
  /// [onProgress] — callback прогресса (0.0 - 1.0)
  Future<List<int>> downloadAudioFile(
    String fileUrl, {
    void Function(double)? onProgress,
  }) async {
    // fileUrl приходит как "/media/audio/note_c4.wav"
    // Нужен абсолютный запрос, минуя baseUrl (/api)
    final url = fileUrl.startsWith('http') ? fileUrl : fileUrl;

    final response = await Dio().get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: _storage.deviceToken != null
            ? {'Authorization': 'Bearer ${_storage.deviceToken}'}
            : null,
      ),
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );
    return response.data!;
  }

  Future<Map<String, dynamic>> submitQuiz(
    int quizId,
    List<Map<String, dynamic>> answers,
  ) async {
    final response = await _dio.post('/quizzes/$quizId/submit', data: {
      'answers': answers,
    });
    return response.data;
  }
}
