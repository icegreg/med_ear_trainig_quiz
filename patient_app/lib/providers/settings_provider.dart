import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage.dart';

final darkModeProvider = StateNotifierProvider<DarkModeNotifier, bool>((ref) {
  final storage = ref.watch(storageProvider);
  return DarkModeNotifier(storage);
});

class DarkModeNotifier extends StateNotifier<bool> {
  final StorageService _storage;

  DarkModeNotifier(this._storage) : super(_storage.isDarkMode);

  Future<void> toggle() async {
    state = !state;
    await _storage.setDarkMode(state);
  }
}
