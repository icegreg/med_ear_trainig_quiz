import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/assignment.dart';
import '../models/audio_file.dart';
import '../models/doctor.dart';
import '../models/patient.dart';
import '../models/quiz.dart';
import '../models/quiz_result.dart';
import '../providers/auth_provider.dart';
import '../providers/audio_library_provider.dart';
import '../providers/patients_provider.dart';
import '../providers/quiz_provider.dart';

final _assignmentsProvider = FutureProvider.family<List<Assignment>, int>((ref, patientId) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getPatientAssignments(patientId);
  return data.map((e) => Assignment.fromJson(e)).toList();
});

final _resultsProvider = FutureProvider.family<List<QuizResult>, int>((ref, patientId) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getPatientResults(patientId);
  return data.map((e) => QuizResult.fromJson(e)).toList();
});

final _doctorsProvider = FutureProvider<List<DoctorListItem>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.listDoctors();
  return data.map((e) => DoctorListItem.fromJson(e)).toList();
});

class PatientDetailScreen extends ConsumerStatefulWidget {
  final int patientId;
  const PatientDetailScreen({super.key, required this.patientId});

  @override
  ConsumerState<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends ConsumerState<PatientDetailScreen> {
  void _refresh() {
    ref.invalidate(patientsProvider);
    ref.invalidate(_assignmentsProvider(widget.patientId));
    ref.invalidate(_resultsProvider(widget.patientId));
  }

  Patient? _findPatient(List<Patient> list) {
    try {
      return list.firstWhere((p) => p.id == widget.patientId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsProvider);
    final assignmentsAsync = ref.watch(_assignmentsProvider(widget.patientId));
    final resultsAsync = ref.watch(_resultsProvider(widget.patientId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Пациент'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/patients'),
        ),
      ),
      body: patientsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (patients) {
          final patient = _findPatient(patients);
          if (patient == null) {
            return const Center(child: Text('Пациент не найден'));
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Info card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(patient.username,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Text('Создан: ${patient.createdAt.toLocal().toString().substring(0, 10)}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Starting sound
                _StartingSoundSection(patient: patient, onChanged: _refresh),
                const SizedBox(height: 16),

                // Actions
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _showAssignQuizDialog(context, patient),
                      icon: const Icon(Icons.add_task),
                      label: const Text('Назначить тест'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showTransferDialog(context, patient),
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Передать'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Assignments
                Text('Назначенные тесты', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                assignmentsAsync.when(
                  data: (assignments) {
                    if (assignments.isEmpty) return const Text('Нет назначений');
                    return Column(
                      children: assignments.map((a) => Card(
                        child: ListTile(
                          title: Text(a.quizTitle),
                          subtitle: Text(a.isCompleted ? 'Пройден' : 'Назначен'),
                          trailing: Chip(
                            label: Text(a.status),
                            backgroundColor: a.isCompleted ? Colors.green[100] : Colors.orange[100],
                          ),
                        ),
                      )).toList(),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Ошибка: $e'),
                ),
                const SizedBox(height: 24),

                // Results
                Text('Результаты', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                resultsAsync.when(
                  data: (results) {
                    if (results.isEmpty) return const Text('Нет результатов');
                    return Column(
                      children: results.map((r) => Card(
                        child: ExpansionTile(
                          title: Text(r.quizTitle),
                          subtitle: Text('Баллы: ${r.score ?? '-'} | ${r.submittedAt.toLocal().toString().substring(0, 16)}'),
                          children: r.answers.map<Widget>((a) => ListTile(
                            dense: true,
                            title: Text('Вопрос ${a['question_id']}'),
                            trailing: Text('${a['answer']}'),
                          )).toList(),
                        ),
                      )).toList(),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Ошибка: $e'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAssignQuizDialog(BuildContext context, Patient patient) {
    showDialog(
      context: context,
      builder: (ctx) => _AssignQuizDialog(
        patientId: patient.id,
        onAssigned: _refresh,
      ),
    );
  }

  void _showTransferDialog(BuildContext context, Patient patient) {
    showDialog(
      context: context,
      builder: (ctx) => _TransferDialog(
        patient: patient,
        onTransferred: () {
          context.go('/patients');
          ref.invalidate(patientsProvider);
        },
      ),
    );
  }
}

class _StartingSoundSection extends ConsumerWidget {
  final Patient patient;
  final VoidCallback onChanged;

  const _StartingSoundSection({required this.patient, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioAsync = ref.watch(allAudioFilesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Стартовый звук', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            audioAsync.when(
              data: (audioFiles) {
                return DropdownButtonFormField<int?>(
                  value: patient.startingSoundId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Не выбран',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Не выбран')),
                    ...audioFiles.map((a) => DropdownMenuItem<int?>(
                      value: a.id,
                      child: Text(a.title),
                    )),
                  ],
                  onChanged: (value) async {
                    final api = ref.read(apiClientProvider);
                    try {
                      await api.setStartingSound(patient.id, value);
                      onChanged();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ошибка')),
                        );
                      }
                    }
                  },
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Ошибка загрузки аудио'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignQuizDialog extends ConsumerStatefulWidget {
  final int patientId;
  final VoidCallback onAssigned;

  const _AssignQuizDialog({required this.patientId, required this.onAssigned});

  @override
  ConsumerState<_AssignQuizDialog> createState() => _AssignQuizDialogState();
}

class _AssignQuizDialogState extends ConsumerState<_AssignQuizDialog> {
  int? _selectedQuizId;
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final quizzesAsync = ref.watch(quizzesProvider);

    return AlertDialog(
      title: const Text('Назначить тест'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            quizzesAsync.when(
              data: (quizzes) => DropdownButtonFormField<int>(
                value: _selectedQuizId,
                decoration: const InputDecoration(
                  labelText: 'Выберите тест',
                  border: OutlineInputBorder(),
                ),
                items: quizzes.map((q) => DropdownMenuItem(
                  value: q.id,
                  child: Text('${q.title} (${q.questionCount} вопр.)'),
                )).toList(),
                onChanged: (v) => setState(() => _selectedQuizId = v),
              ),
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => const Text('Ошибка загрузки'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _loading || _selectedQuizId == null ? null : _assign,
          child: _loading
              ? const SizedBox(height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Назначить'),
        ),
      ],
    );
  }

  Future<void> _assign() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      await api.assignQuiz(widget.patientId, _selectedQuizId!);
      widget.onAssigned();
      if (mounted) Navigator.pop(context);
    } on DioException catch (e) {
      setState(() {
        _error = (e.response?.data is Map)
            ? e.response!.data['message'] ?? 'Ошибка'
            : 'Ошибка назначения';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _TransferDialog extends ConsumerStatefulWidget {
  final Patient patient;
  final VoidCallback onTransferred;

  const _TransferDialog({required this.patient, required this.onTransferred});

  @override
  ConsumerState<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<_TransferDialog> {
  String? _selectedDoctorId;
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final doctorsAsync = ref.watch(_doctorsProvider);

    return AlertDialog(
      title: const Text('Передать пациента'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Пациент: ${widget.patient.username}'),
            const SizedBox(height: 16),
            doctorsAsync.when(
              data: (doctors) => DropdownButtonFormField<String>(
                value: _selectedDoctorId,
                decoration: const InputDecoration(
                  labelText: 'Выберите врача',
                  border: OutlineInputBorder(),
                ),
                items: doctors.map((d) => DropdownMenuItem(
                  value: d.id,
                  child: Text('${d.fullName}${d.clinic.isNotEmpty ? ' (${d.clinic})' : ''}'),
                )).toList(),
                onChanged: (v) => setState(() => _selectedDoctorId = v),
              ),
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => const Text('Ошибка загрузки'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _loading || _selectedDoctorId == null ? null : _transfer,
          child: _loading
              ? const SizedBox(height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Передать'),
        ),
      ],
    );
  }

  Future<void> _transfer() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      await api.transferPatient(widget.patient.id, _selectedDoctorId!);
      widget.onTransferred();
      if (mounted) Navigator.pop(context);
    } on DioException catch (e) {
      setState(() {
        _error = (e.response?.data is Map)
            ? e.response!.data['message'] ?? 'Ошибка'
            : 'Ошибка передачи';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
