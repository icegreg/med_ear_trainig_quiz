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
    final existing = state.files;
    final files = <int, Uint8List>{};
    // Прогресс по каждому файлу (0..1) для агрегированного индикатора.
    final progressById = <int, double>{};

    void publish() {
      final overall =
          progressById.values.fold<double>(0, (a, b) => a + b) / totalFiles;
      state = AudioCacheState(
        files: files,
        downloadProgress: overall,
        statusText: 'Скачивание ${files.length}/$totalFiles',
      );
    }

    Future<void> downloadOne(dynamic audio) async {
      final id = audio['id'] as int;
      final fileUrl = audio['file'] as String;

      // Уже в кэше — переиспользуем.
      if (existing.containsKey(id)) {
        files[id] = existing[id]!;
        progressById[id] = 1.0;
        publish();
        return;
      }

      progressById[id] = 0.0;
      final bytes = await _api.downloadAudioFile(
        fileUrl,
        onProgress: (fileProgress) {
          progressById[id] = fileProgress;
          publish();
        },
      );
      files[id] = Uint8List.fromList(bytes);
      progressById[id] = 1.0;
      publish();
    }

    // Параллельная загрузка с ограничением одновременных запросов.
    // Воркеры тянут задачи из общего индекса (инкремент атомарен в
    // однопоточном event loop'е Dart — между чтением и await нет переключений).
    const maxConcurrent = 4;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= audioList.length) break;
        await downloadOne(audioList[i]);
      }
    }

    final workerCount =
        totalFiles < maxConcurrent ? totalFiles : maxConcurrent;
    await Future.wait(List.generate(workerCount, (_) => worker()));

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
