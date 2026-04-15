import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/patients_provider.dart';

class PatientsListScreen extends ConsumerStatefulWidget {
  const PatientsListScreen({super.key});

  @override
  ConsumerState<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends ConsumerState<PatientsListScreen> {
  String _search = '';

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
                hintText: 'Поиск по имени...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: patientsAsync.when(
              data: (patients) {
                final filtered = _search.isEmpty
                    ? patients
                    : patients.where((p) => p.username.toLowerCase().contains(_search)).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('Нет пациентов'));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(patientsProvider),
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final p = filtered[i];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(p.username),
                        subtitle: Text('Создан: ${p.createdAt.toLocal().toString().substring(0, 10)}'),
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
