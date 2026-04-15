import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/patients_provider.dart';

final _profileProvider = FutureProvider((ref) async {
  final api = ref.watch(apiClientProvider);
  return await api.getProfile();
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(_profileProvider);
    final patients = ref.watch(patientsProvider);
    final notifs = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_profileProvider);
          ref.invalidate(patientsProvider);
          ref.read(notificationsProvider.notifier).fetch();
        },
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Welcome
            profile.when(
              data: (data) => Text(
                'Добро пожаловать, ${data['first_name']} ${data['last_name']}!',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Ошибка загрузки профиля'),
            ),
            const SizedBox(height: 24),

            // Cards row
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _DashCard(
                  icon: Icons.people,
                  title: 'Пациенты',
                  value: patients.when(
                    data: (list) => '${list.length}',
                    loading: () => '...',
                    error: (_, __) => '-',
                  ),
                  onTap: () => context.go('/patients'),
                ),
                _DashCard(
                  icon: Icons.notifications,
                  title: 'Непрочитанные',
                  value: '${notifs.unreadCount}',
                  onTap: () => context.go('/notifications'),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Quick actions
            Text('Быстрые действия', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.person_add),
                  label: const Text('Добавить пациента'),
                  onPressed: () => context.go('/patients/add'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.library_music),
                  label: const Text('Библиотека звуков'),
                  onPressed: () => context.go('/audio-library'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.quiz),
                  label: const Text('Список тестов'),
                  onPressed: () => context.go('/quizzes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  const _DashCard({
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(value, style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 4),
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
