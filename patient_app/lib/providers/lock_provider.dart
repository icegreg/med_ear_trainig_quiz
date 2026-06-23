import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage.dart';

/// Слой блокировки поверх авторизации.
///
/// `true` — приложение заблокировано и требует код доступа (или пароль).
/// При холодном старте, если пользователь залогинен и токен жив,
/// приложение считается заблокированным.
final lockProvider = StateNotifierProvider<LockNotifier, bool>((ref) {
  final storage = ref.watch(storageProvider);
  return LockNotifier(storage);
});

class LockNotifier extends StateNotifier<bool> {
  final StorageService _storage;

  LockNotifier(this._storage) : super(_storage.isLoggedIn);

  /// Заблокировать (после возврата из фона по таймауту).
  void lock() {
    if (_storage.isLoggedIn) state = true;
  }

  /// Разблокировать (успешный ввод ПИН или вход по паролю).
  void unlock() => state = false;
}
