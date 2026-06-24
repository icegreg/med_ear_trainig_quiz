import 'dart:typed_data';

/// Web-заглушка: файловой системы нет, играем из памяти.
Future<String?> writeTempAudio(String key, Uint8List bytes) async => null;
