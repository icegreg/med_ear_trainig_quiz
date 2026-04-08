import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/storage.dart';

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiClientProvider);
  final storage = ref.watch(storageProvider);
  return AuthNotifier(api, storage);
});

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final String? error;

  const AuthState({this.status = AuthStatus.initial, this.error});

  AuthState copyWith({AuthStatus? status, String? error}) =>
      AuthState(status: status ?? this.status, error: error ?? this.error);
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;
  final StorageService _storage;

  AuthNotifier(this._api, this._storage)
      : super(AuthState(
          status: _storage.isLoggedIn
              ? AuthStatus.authenticated
              : AuthStatus.unauthenticated,
        ));

  Future<void> login(String username, String password) async {
    state = const AuthState(status: AuthStatus.loading);
    try {
      final data = await _api.obtainDeviceToken(
        username: username,
        password: password,
      );
      await _storage.setDeviceToken(data['token']);
      await _storage.setPatientId(data['patient_id']);
      await _storage.setLastUsername(username);
      state = const AuthState(status: AuthStatus.authenticated);
    } catch (e) {
      state = const AuthState(
        status: AuthStatus.error,
        error: 'Неверный логин или пароль',
      );
    }
  }

  Future<void> logout() async {
    await _storage.clearDeviceToken();
    // lastUsername НЕ очищаем — для автозаполнения
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Вызывается из interceptor при 401
  void forceLogout() {
    _storage.clearDeviceToken();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}
