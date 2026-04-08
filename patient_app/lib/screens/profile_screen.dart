import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/patient_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = ref.watch(patientProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: patient.when(
        data: (p) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.person, size: 48,
                  color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 24),
            _InfoTile(
              icon: Icons.person_outline,
              label: 'Пользователь',
              value: p.username,
            ),
            _InfoTile(
              icon: Icons.medical_services_outlined,
              label: 'Врач',
              value: p.doctorId ?? 'Не назначен',
            ),
            const SizedBox(height: 48),
            OutlinedButton.icon(
              onPressed: () => _confirmLogout(context, ref),
              icon: const Icon(Icons.logout),
              label: const Text('Выйти'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                minimumSize: const Size(double.infinity, 56),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Ошибка загрузки профиля')),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 28, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(value, style: theme.textTheme.bodyLarge),
            ],
          ),
        ],
      ),
    );
  }
}
