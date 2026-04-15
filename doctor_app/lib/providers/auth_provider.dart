import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/storage.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final String? error;

  const AuthState({this.status = AuthStatus.initial, this.error});

  AuthState copyWith({AuthStatus? status, String? error}) =>
      AuthState(status: status ?? this.status, error: error);
}

class AuthNotifier extends StateNotifier<AuthState> {
  final StorageService _storage;
  final ApiClient _api;

  AuthNotifier(this._storage, this._api) : super(const AuthState()) {
    _api.onForceLogout = forceLogout;
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final loggedIn = await _storage.isLoggedIn;
    state = AuthState(
      status: loggedIn ? AuthStatus.authenticated : AuthStatus.unauthenticated,
    );
  }

  Future<void> login(String username, String password) async {
    state = const AuthState(status: AuthStatus.loading);
    try {
      final data = await _api.login(username, password);
      await _storage.setTokens(access: data['access'], refresh: data['refresh']);
      state = const AuthState(status: AuthStatus.authenticated);
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] ?? 'Ошибка входа';
      state = AuthState(status: AuthStatus.error, error: msg.toString());
    } catch (e) {
      state = AuthState(status: AuthStatus.error, error: e.toString());
    }
  }

  Future<void> logout() async {
    await _storage.clearTokens();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void forceLogout() {
    _storage.clearTokens();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

// Providers
final storageProvider = Provider<StorageService>((ref) => throw UnimplementedError());
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(storageProvider);
  return ApiClient(storage);
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final storage = ref.watch(storageProvider);
  final api = ref.watch(apiClientProvider);
  return AuthNotifier(storage, api);
});
