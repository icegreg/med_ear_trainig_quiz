import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import 'log_buffer.dart';
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
        options.extra['_log_started_at'] =
            DateTime.now().millisecondsSinceEpoch;
        handler.next(options);
      },
      onResponse: (response, handler) {
        _logRequest(
          response.requestOptions,
          statusCode: response.statusCode,
          response: response,
        );
        handler.next(response);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          // Не сбрасываем на auth-эндпоинтах (логин/рефреш)
          final path = error.requestOptions.path;
          if (!path.startsWith('/auth/')) {
            _ref.read(authProvider.notifier).forceLogout();
          }
        }
        _logRequest(
          error.requestOptions,
          statusCode: error.response?.statusCode,
          response: error.response,
          error: error,
        );
        handler.next(error);
      },
    ));
  }

  void _logRequest(
    RequestOptions options, {
    int? statusCode,
    Response? response,
    DioException? error,
  }) {
    // Не логируем сам EP логов (LogBuffer.add его тоже отсеивает, но руками
    // отсечь дешевле — не создавать LogBuffer для пустых вызовов).
    if (options.path.endsWith(kLogEndpointPath)) return;

    try {
      final startedAt = options.extra['_log_started_at'] as int?;
      final durationMs = startedAt == null
          ? null
          : DateTime.now().millisecondsSinceEpoch - startedAt;

      final buffer = _ref.read(logBufferProvider);
      buffer.add(
        method: options.method,
        path: options.path,
        statusCode: statusCode,
        durationMs: durationMs,
        errorType: error?.type.name,
        errorMessage: error?.message,
        requestPayload: options.data,
        responseBody: response?.data is String
            ? response!.data as String
            : (response?.data == null ? null : response!.data.toString()),
      );
    } catch (_) {
      // Никогда не падать из-за логирования
    }
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
  /// [fileUrl] — относительный (`/media/audio/x.wav`) или абсолютный URL из AudioFile.file.
  /// [onProgress] — callback прогресса (0.0 - 1.0)
  Future<List<int>> downloadAudioFile(
    String fileUrl, {
    void Function(double)? onProgress,
  }) async {
    // /media/... лежит вне /api, поэтому строим абсолютный URL от origin
    // (Uri.resolve отбрасывает path baseUrl при absolute path аргументе).
    final absoluteUrl = fileUrl.startsWith('http')
        ? fileUrl
        : Uri.parse(_dio.options.baseUrl).resolve(fileUrl).toString();

    final response = await _dio.get<List<int>>(
      absoluteUrl,
      options: Options(responseType: ResponseType.bytes),
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
