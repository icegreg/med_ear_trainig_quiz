import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/quiz.dart';
import '../providers/quiz_provider.dart';

class QuizListScreen extends ConsumerWidget {
  const QuizListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quizzes = ref.watch(quizListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Тесты')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(quizListProvider),
        child: quizzes.when(
          data: (list) {
            if (list.isEmpty) {
              return const Center(
                child:
                    Text('Нет назначенных тестов', style: TextStyle(fontSize: 18)),
              );
            }

            final available =
                list.where((q) => q.isAvailable).toList();
            final upcoming =
                list.where((q) => q.isUpcoming).toList();
            final completed =
                list.where((q) => q.isCompleted).toList();
            final expired =
                list.where((q) => q.isExpired).toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (available.isNotEmpty) ...[
                  _SectionHeader('Доступные', theme),
                  ...available.map((q) => _QuizCard(quiz: q)),
                ],
                if (upcoming.isNotEmpty) ...[
                  _SectionHeader('Будут доступны', theme),
                  ...upcoming.map((q) => _QuizCard(quiz: q)),
                ],
                if (expired.isNotEmpty) ...[
                  _SectionHeader('Просрочены', theme),
                  ...expired.map((q) => _QuizCard(quiz: q)),
                ],
                if (completed.isNotEmpty) ...[
                  _SectionHeader('Пройдены', theme),
                  ...completed.map((q) => _QuizCard(quiz: q)),
                ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 8),
                const Text('Ошибка загрузки'),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => ref.invalidate(quizListProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader(this.title, this.theme);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title, style: theme.textTheme.headlineMedium),
    );
  }
}

class _QuizCard extends StatelessWidget {
  final QuizListItem quiz;

  const _QuizCard({required this.quiz});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final IconData icon;
    final Color iconColor;
    if (quiz.isCompleted) {
      icon = Icons.check_circle;
      iconColor = Colors.green;
    } else if (quiz.isExpired) {
      icon = Icons.timer_off;
      iconColor = Colors.grey;
    } else if (quiz.isUpcoming) {
      icon = Icons.schedule;
      iconColor = Colors.orange;
    } else {
      icon = Icons.assignment;
      iconColor = theme.colorScheme.primary;
    }

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(icon, size: 40, color: iconColor),
        title: Text(quiz.title,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_statusText, style: TextStyle(color: iconColor)),
            if (quiz.isDeadlineSoon)
              _DeadlineBadge(days: quiz.daysUntilDeadline!),
            if (quiz.isUpcoming && quiz.startsAt != null)
              Text(
                'Доступен с ${DateFormat('dd.MM.yyyy HH:mm').format(quiz.startsAt!.toLocal())}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        trailing: _trailing(context),
      ),
    );
  }

  String get _statusText {
    if (quiz.isCompleted) return 'Пройден';
    if (quiz.isExpired) return 'Просрочен';
    if (quiz.isUpcoming) return 'Ожидание';
    return 'Доступен';
  }

  Widget? _trailing(BuildContext context) {
    if (quiz.isCompleted || quiz.isExpired) return null;
    if (quiz.isUpcoming) {
      return const Icon(Icons.lock_outline, color: Colors.orange);
    }
    return FilledButton(
      onPressed: () => context.push('/quiz/${quiz.id}/prep'),
      child: const Text('Начать'),
    );
  }
}

class _DeadlineBadge extends StatelessWidget {
  final int days;
  const _DeadlineBadge({required this.days});

  @override
  Widget build(BuildContext context) {
    final text = days == 0
        ? 'Последний день!'
        : 'Осталось $days дн.';
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: days <= 1 ? Colors.red : Colors.orange,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}
