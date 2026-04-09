import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/result_provider.dart';

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(resultListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Результаты')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(resultListProvider),
        child: results.when(
          data: (list) {
            if (list.isEmpty) {
              return const Center(
                child: Text('Пройденных тестов пока нет',
                    style: TextStyle(fontSize: 18)),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final r = list[i];
                final date = DateFormat('dd.MM.yyyy HH:mm')
                    .format(r.submittedAt.toLocal());
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const Icon(Icons.check_circle,
                        size: 40, color: Colors.green),
                    title: Text(r.quizTitle,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text(date),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Ошибка загрузки')),
        ),
      ),
    );
  }
}
