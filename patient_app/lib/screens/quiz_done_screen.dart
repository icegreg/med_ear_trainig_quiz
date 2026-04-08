import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class QuizDoneScreen extends StatelessWidget {
  const QuizDoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_done, size: 100, color: Colors.green),
                const SizedBox(height: 32),
                Text(
                  'Тест завершён!',
                  style: theme.textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Ваши ответы успешно загружены на сервер.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: () => context.go('/'),
                  child: const Text('На главную'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
