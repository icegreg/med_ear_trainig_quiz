import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/date_utils.dart';
import '../providers/patients_provider.dart';

class PatientsListScreen extends ConsumerStatefulWidget {
  const PatientsListScreen({super.key});

  @override
  ConsumerState<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _CountBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _CountBadge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color.withAlpha(100)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

class _PatientsListScreenState extends ConsumerState<PatientsListScreen> {
  String _search = '';

  String _formatBirthDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Пациенты')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/patients/add'),
        icon: const Icon(Icons.person_add),
        label: const Text('Добавить'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Поиск по фамилии или имени...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: patientsAsync.when(
              data: (patients) {
                final filtered = _search.isEmpty
                    ? patients
                    : patients.where((p) {
                        return p.lastName.toLowerCase().contains(_search) ||
                            p.firstName.toLowerCase().contains(_search);
                      }).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('Нет пациентов'));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(patientsProvider),
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final p = filtered[i];
                      final bd = p.birthDate;
                      final topLine = <String>[
                        if (bd != null) 'Д.р.: ${_formatBirthDate(bd)} (${formatAge(bd)})',
                        '@${p.username}',
                      ].join(' · ');
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(p.displayName),
                        isThreeLine: true,
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(topLine),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              children: [
                                _CountBadge(
                                  icon: Icons.pending_actions,
                                  label: 'Активных: ${p.assignedCount}',
                                  color: p.assignedCount > 0 ? Colors.orange : Colors.grey,
                                ),
                                _CountBadge(
                                  icon: Icons.check_circle,
                                  label: 'Пройдено: ${p.completedCount}',
                                  color: p.completedCount > 0 ? Colors.green : Colors.grey,
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: p.startingSoundId != null
                            ? const Icon(Icons.music_note, color: Colors.green)
                            : null,
                        onTap: () => context.go('/patients/${p.id}'),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Ошибка: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
