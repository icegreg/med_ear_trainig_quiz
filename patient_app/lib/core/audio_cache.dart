import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Кэш скачанных аудио-файлов (в памяти). Ключ — audio file ID.
final audioCacheProvider = StateNotifierProvider<AudioCacheNotifier, AudioCacheState>((ref) {
  final api = ref.watch(apiClientProvider);
  return AudioCacheNotifier(api);
});

class AudioCacheState {
  /// id → bytes скачанного файла
  final Map<int, Uint8List> files;

  /// Общий прогресс скачивания (0.0 - 1.0), null если не качаем
  final double? downloadProgress;

  /// Текст статуса
  final String? statusText;

  /// Всё скачано
  final bool isReady;

  const AudioCacheState({
    this.files = const {},
    this.downloadProgress,
    this.statusText,
    this.isReady = false,
  });
}

class AudioCacheNotifier extends StateNotifier<AudioCacheState> {
  final ApiClient _api;

  AudioCacheNotifier(this._api) : super(const AudioCacheState());

  /// Скачать все аудио-файлы для квиза.
  Future<void> downloadForQuiz(int quizId) async {
    state = const AudioCacheState(
      downloadProgress: 0,
      statusText: 'Получение списка файлов...',
    );

    // Получаем список аудио
    final audioList = await _api.getQuizAudio(quizId);
    if (audioList.isEmpty) {
      state = const AudioCacheState(isReady: true, statusText: 'Нет аудио-файлов');
      return;
    }

    final totalFiles = audioList.length;
    final files = <int, Uint8List>{};

    for (var i = 0; i < audioList.length; i++) {
      final audio = audioList[i];
      final id = audio['id'] as int;
      final fileUrl = audio['file'] as String;
      final title = audio['title'] as String;

      // Если уже в кэше — пропускаем
      if (state.files.containsKey(id)) {
        files[id] = state.files[id]!;
        continue;
      }

      state = AudioCacheState(
        files: files,
        downloadProgress: i / totalFiles,
        statusText: 'Скачивание ${i + 1}/$totalFiles: $title',
      );

      final bytes = await _api.downloadAudioFile(
        fileUrl,
        onProgress: (fileProgress) {
          final overall = (i + fileProgress) / totalFiles;
          state = AudioCacheState(
            files: files,
            downloadProgress: overall,
            statusText: 'Скачивание ${i + 1}/$totalFiles: $title',
          );
        },
      );

      files[id] = Uint8List.fromList(bytes);
    }

    state = AudioCacheState(
      files: Map.unmodifiable(files),
      downloadProgress: 1.0,
      statusText: 'Все файлы загружены',
      isReady: true,
    );
  }

  /// Получить скачанный файл по ID.
  Uint8List? getFile(int audioFileId) => state.files[audioFileId];

  /// Очистить кэш.
  void clear() {
    state = const AudioCacheState();
  }
}
