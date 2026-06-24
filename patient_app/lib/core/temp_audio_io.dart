import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Пишет байты во временный WAV-файл (перезаписывая прежний с тем же ключом)
/// и возвращает путь. Имя детерминированное по [key], чтобы не копить мусор.
Future<String?> writeTempAudio(String key, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/quiz_audio_$key.wav');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
