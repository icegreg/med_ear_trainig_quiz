import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/notification.dart';
import 'auth_provider.dart';

class NotificationsState {
  final List<AppNotification> notifications;
  final int unreadCount;
  final bool loading;

  const NotificationsState({
    this.notifications = const [],
    this.unreadCount = 0,
    this.loading = false,
  });

  NotificationsState copyWith({
    List<AppNotification>? notifications,
    int? unreadCount,
    bool? loading,
  }) =>
      NotificationsState(
        notifications: notifications ?? this.notifications,
        unreadCount: unreadCount ?? this.unreadCount,
        loading: loading ?? this.loading,
      );
}

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  final ApiClient _api;
  Timer? _timer;

  NotificationsNotifier(this._api) : super(const NotificationsState()) {
    fetch();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => fetch());
  }

  Future<void> fetch() async {
    try {
      final data = await _api.getNotifications();
      final list = (data['notifications'] as List)
          .map((e) => AppNotification.fromJson(e))
          .toList();
      state = NotificationsState(
        notifications: list,
        unreadCount: data['unread_count'] ?? 0,
      );
    } catch (_) {}
  }

  Future<void> markRead(int id) async {
    try {
      await _api.markNotificationRead(id);
      await fetch();
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, NotificationsState>((ref) {
  final api = ref.watch(apiClientProvider);
  return NotificationsNotifier(api);
});
