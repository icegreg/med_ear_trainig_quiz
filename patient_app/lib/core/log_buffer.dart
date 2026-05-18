import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_client.dart';
import 'constants.dart';

/// Эндпоинт, куда отправляется batch логов. Запросы к нему НЕ логируются
/// (защита от рекурсии).
const String kLogEndpointPath = '/patients/logs';

/// Пути, для которых маскируем тело запроса (логины/пароли и т.п.).
const List<String> _maskedPathPrefixes = ['/auth/'];

const Duration _flushInterval = Duration(seconds: 30);
const int _flushThreshold = 20;
const int _maxBufferSize = 500; // защита от безграничного роста при offline

/// Буфер клиентских логов. Раз в _flushInterval или при наборе _flushThreshold
/// записей флашит batch на сервер. Если сервер ответил {enabled: false} —
/// прекращает приём новых записей.
class LogBuffer {
  LogBuffer(this._dio);

  final Dio _dio;
  final Queue<Map<String, dynamic>> _queue = Queue();
  bool _enabled = false;
  Timer? _timer;
  bool _flushing = false;
  PackageInfo? _packageInfo;

  bool get enabled => _enabled;

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (_enabled) {
      _timer ??= Timer.periodic(_flushInterval, (_) => _flushSafe());
    } else {
      _timer?.cancel();
      _timer = null;
      _queue.clear();
    }
  }

  void add({
    required String method,
    required String path,
    int? statusCode,
    int? durationMs,
    String? errorType,
    String? errorMessage,
    dynamic requestPayload,
    String? responseBody,
  }) {
    if (!_enabled) return;
    if (path.endsWith(kLogEndpointPath)) return; // не логируем сам EP логов

    final masked = _shouldMask(path)
        ? '***masked***'
        : _truncatePayload(requestPayload);

    _queue.add({
      'client_ts': DateTime.now().toUtc().toIso8601String(),
      'method': method,
      'path': path,
      'status_code': statusCode,
      'duration_ms': durationMs,
      'error_type': errorType,
      'error_message': errorMessage,
      'request_payload': masked,
      'response_body': responseBody == null ? null : _truncate(responseBody, 4096),
      'app_version': _packageInfo?.version,
      'build_number': _packageInfo?.buildNumber,
      'platform': _platformName(),
      'flavor': kFlavor,
    });

    if (_queue.length >= _flushThreshold) {
      _flushSafe();
    }
    while (_queue.length > _maxBufferSize) {
      _queue.removeFirst();
    }
  }

  Future<void> _flushSafe() async {
    try {
      await flush();
    } catch (_) {
      // глотаем — не хотим логировать ошибку отправки логов
    }
  }

  Future<void> flush() async {
    if (!_enabled || _flushing || _queue.isEmpty) return;
    _flushing = true;
    try {
      _packageInfo ??= await PackageInfo.fromPlatform();
      for (final entry in _queue) {
        entry['app_version'] ??= _packageInfo!.version;
        entry['build_number'] ??= _packageInfo!.buildNumber;
      }
      final batch = List<Map<String, dynamic>>.from(_queue);
      final response = await _dio.post(
        kLogEndpointPath,
        data: {'entries': batch},
      );
      if (response.data is Map && response.data['enabled'] == false) {
        setEnabled(false);
        return;
      }
      for (int i = 0; i < batch.length; i++) {
        if (_queue.isNotEmpty) _queue.removeFirst();
      }
    } finally {
      _flushing = false;
    }
  }

  bool _shouldMask(String path) {
    for (final prefix in _maskedPathPrefixes) {
      if (path.contains(prefix)) return true;
    }
    return false;
  }

  dynamic _truncatePayload(dynamic payload) {
    if (payload == null) return null;
    if (payload is String) return _truncate(payload, 4096);
    return payload;
  }

  String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…[truncated ${s.length - max}b]';
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      if (Platform.isLinux) return 'linux';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isWindows) return 'windows';
    } catch (_) {}
    return 'unknown';
  }

  void dispose() {
    _timer?.cancel();
    _queue.clear();
  }
}

/// Создаётся один раз; берёт Dio из ApiClient. По умолчанию выключен —
/// включается, когда придёт patient profile с logging_enabled=true.
final logBufferProvider = Provider<LogBuffer>((ref) {
  final api = ref.read(apiClientProvider);
  final buffer = LogBuffer(api.dio);
  ref.onDispose(buffer.dispose);
  return buffer;
});
