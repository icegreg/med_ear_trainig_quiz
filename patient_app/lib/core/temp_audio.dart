import 'dart:typed_data';

import 'temp_audio_stub.dart'
    if (dart.library.io) 'temp_audio_io.dart' as impl;

/// Записывает аудио-байты во временный файл и возвращает путь к нему.
///
/// На нативных платформах (Android/iOS) just_audio устойчиво играет звук
/// из файла (`setFilePath`), тогда как in-memory `StreamAudioSource` через
/// локальный прокси на Android часто проигрывается без звука. На web файловой
/// системы нет — там возвращается `null`, и вызывающий код играет из памяти.
Future<String?> writeTempAudio(String key, Uint8List bytes) =>
    impl.writeTempAudio(key, bytes);
