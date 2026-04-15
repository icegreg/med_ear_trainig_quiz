import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/quiz_provider.dart';

class QuizListScreen extends ConsumerWidget {
  const QuizListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quizzesAsync = ref.watch(quizzesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Тесты')),
      body: quizzesAsync.when(
        data: (quizzes) {
          if (quizzes.isEmpty) {
            return const Center(child: Text('Нет доступных тестов'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(quizzesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: quizzes.length,
              itemBuilder: (context, i) {
                final q = quizzes[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.quiz)),
                    title: Text(q.title),
                    subtitle: Text(q.description.isNotEmpty
                        ? q.description
                        : '${q.questionCount} вопросов'),
                    trailing: Chip(label: Text('${q.questionCount} вопр.')),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
      ),
    );
  }
}
