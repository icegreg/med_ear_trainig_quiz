import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/notifications_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Уведомления${state.unreadCount > 0 ? ' (${state.unreadCount})' : ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(notificationsProvider.notifier).fetch(),
          ),
        ],
      ),
      body: state.notifications.isEmpty
          ? const Center(child: Text('Нет уведомлений'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.notifications.length,
              itemBuilder: (context, i) {
                final n = state.notifications[i];
                final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(n.createdAt.toLocal());
                return Card(
                  color: n.isRead ? null : Theme.of(context).colorScheme.primaryContainer,
                  child: ListTile(
                    leading: Icon(
                      _iconForType(n.type),
                      color: n.isRead ? null : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(n.message),
                    subtitle: Text(dateStr),
                    trailing: n.isRead
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.done),
                            tooltip: 'Прочитано',
                            onPressed: () =>
                                ref.read(notificationsProvider.notifier).markRead(n.id),
                          ),
                  ),
                );
              },
            ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'patient_transferred':
        return Icons.swap_horiz;
      case 'patient_added':
        return Icons.person_add;
      case 'quiz_completed':
        return Icons.check_circle;
      default:
        return Icons.notifications;
    }
  }
}
