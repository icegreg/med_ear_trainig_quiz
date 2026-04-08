import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/patient_provider.dart';
import '../providers/quiz_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = ref.watch(patientProvider);
    final quizzes = ref.watch(quizListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(patientProvider);
          ref.invalidate(quizListProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            patient.when(
              data: (p) => Text(
                'Здравствуйте, ${p.username}',
                style: theme.textTheme.headlineMedium,
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),
            quizzes.when(
              data: (list) {
                final available = list.where((q) => q.isAvailable).length;
                final upcoming = list.where((q) => q.isUpcoming).length;
                final completed = list.where((q) => q.isCompleted).length;
                final deadlineSoon =
                    list.where((q) => q.isDeadlineSoon).toList();

                return Column(
                  children: [
                    // Уведомление о дедлайнах
                    if (deadlineSoon.isNotEmpty)
                      Card(
                        color: Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber,
                                  color: Colors.orange, size: 32),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${deadlineSoon.length} тест(ов) с дедлайном в ближайшие 3 дня!',
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (deadlineSoon.isNotEmpty) const SizedBox(height: 12),
                    _StatCard(
                      icon: Icons.assignment,
                      title: 'Доступно',
                      value: '$available',
                      color: theme.colorScheme.primary,
                      onTap: () => context.go('/quizzes'),
                    ),
                    if (upcoming > 0) ...[
                      const SizedBox(height: 12),
                      _StatCard(
                        icon: Icons.schedule,
                        title: 'Ожидание',
                        value: '$upcoming',
                        color: Colors.orange,
                        onTap: () => context.go('/quizzes'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _StatCard(
                      icon: Icons.check_circle,
                      title: 'Пройдено',
                      value: '$completed',
                      color: Colors.green,
                      onTap: () => context.go('/results'),
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Center(
                child: Column(
                  children: [
                    const Icon(Icons.cloud_off, size: 48),
                    const SizedBox(height: 8),
                    Text('Не удалось загрузить данные',
                        style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(quizListProvider),
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge),
                    Text(value,
                        style: theme.textTheme.headlineLarge
                            ?.copyWith(color: color)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
