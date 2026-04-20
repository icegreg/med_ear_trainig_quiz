import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/date_utils.dart';
import '../core/media_auth.dart';
import '../core/web_audio_player.dart';

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
                        Row(
                          children: [
                            Expanded(
                              child: Text(patient.displayName,
                                  style: Theme.of(context).textTheme.headlineSmall),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: 'Редактировать ФИО',
                              onPressed: () => _showFioDialog(context, patient),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Логин: ${patient.username}',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text('Создан: ${patient.createdAt.toLocal().toString().substring(0, 10)}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Birth date
                _BirthDateSection(patient: patient, onChanged: _refresh),
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
                      children: assignments.map((a) => _AssignmentTile(
                        assignment: a,
                        onUnassign: () => _confirmUnassign(context, a.id, a.quizTitle),
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

  Future<void> _confirmUnassign(BuildContext context, int assignmentId, String quizTitle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Снять назначение?'),
        content: Text('Пациенту больше не будет доступен тест «$quizTitle».'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Снять')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiClientProvider).unassignQuiz(widget.patientId, assignmentId);
      _refresh();
      ref.invalidate(patientsProvider);
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data is Map && e.response!.data['message'] != null)
          ? e.response!.data['message'] as String
          : 'Ошибка';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _showFioDialog(BuildContext context, Patient patient) {
    showDialog(
      context: context,
      builder: (ctx) => _FioDialog(patient: patient, onSaved: _refresh),
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

class _StartingSoundSection extends ConsumerStatefulWidget {
  final Patient patient;
  final VoidCallback onChanged;

  const _StartingSoundSection({required this.patient, required this.onChanged});

  @override
  ConsumerState<_StartingSoundSection> createState() => _StartingSoundSectionState();
}

class _StartingSoundSectionState extends ConsumerState<_StartingSoundSection> {
  final _player = WebAudioPlayer();
  int? _playingId;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _select(int? audioId) async {
    if (audioId == widget.patient.startingSoundId) return;
    final api = ref.read(apiClientProvider);
    try {
      await api.setStartingSound(widget.patient.id, audioId);
      widget.onChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка')),
        );
      }
    }
  }

  Future<void> _togglePlay(int id, String url) async {
    _player.warmup();
    if (_playingId == id) {
      await _player.stopWithFadeOut();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    try {
      await _player.stopWithFadeOut();
      final token = await ref.read(storageProvider).accessToken;
      if (mounted) setState(() => _playingId = id);
      await _player.playWithFadeIn(withAuthToken(url, token));
      if (mounted) setState(() => _playingId = null);
    } catch (_) {
      if (mounted) setState(() => _playingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioAsync = ref.watch(allAudioFilesProvider);
    final selectedId = widget.patient.startingSoundId;

    String selectedLabel = 'Не выбран';
    audioAsync.whenData((files) {
      if (selectedId != null) {
        for (final a in files) {
          if (a.id == selectedId) {
            selectedLabel = a.title;
            break;
          }
        }
      }
    });

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text('Стартовый звук', style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(selectedLabel),
        childrenPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          audioAsync.when(
            data: (audioFiles) {
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SoundTile(
                    icon: Icons.volume_off,
                    label: 'Не выбран',
                    selected: widget.patient.startingSoundId == null,
                    onTap: () => _select(null),
                  ),
                  ...audioFiles.map((a) => _SoundTile(
                        icon: Icons.music_note,
                        label: a.title,
                        selected: widget.patient.startingSoundId == a.id,
                        playing: _playingId == a.id,
                        onTap: () => _select(a.id),
                        onPlay: () => _togglePlay(a.id, a.fileUrl),
                      )),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('Ошибка загрузки аудио'),
          ),
        ],
      ),
    );
  }
}

class _SoundTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback? onPlay;

  const _SoundTile({
    required this.icon,
    required this.label,
    required this.selected,
    this.playing = false,
    required this.onTap,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final borderColor = selected ? scheme.primary : scheme.outlineVariant;

    return SizedBox(
      width: 130,
      height: 92,
      child: Stack(
        children: [
          Positioned.fill(
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: selected ? 2 : 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: fg, size: 28),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onPlay != null)
            Positioned(
              top: 2,
              right: 2,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPlay,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      playing ? Icons.stop_circle : Icons.play_circle,
                      size: 22,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BirthDateSection extends ConsumerWidget {
  final Patient patient;
  final VoidCallback onChanged;

  const _BirthDateSection({required this.patient, required this.onChanged});

  String _format(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: patient.birthDate ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Дата рождения',
    );
    if (picked == null) return;
    await _save(context, ref, picked);
  }

  Future<void> _save(BuildContext context, WidgetRef ref, DateTime? date) async {
    final api = ref.read(apiClientProvider);
    try {
      await api.setBirthDate(patient.id, date);
      onChanged();
    } on DioException catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка сохранения')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bd = patient.birthDate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Дата рождения', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    bd == null ? 'Не указана' : '${_format(bd)} (${formatAge(bd)})',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_calendar),
                  tooltip: 'Изменить',
                  onPressed: () => _pick(context, ref),
                ),
                if (bd != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Очистить',
                    onPressed: () => _save(context, ref, null),
                  ),
              ],
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
            Text('Пациент: ${widget.patient.displayName}'),
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

class _FioDialog extends ConsumerStatefulWidget {
  final Patient patient;
  final VoidCallback onSaved;

  const _FioDialog({required this.patient, required this.onSaved});

  @override
  ConsumerState<_FioDialog> createState() => _FioDialogState();
}

class _FioDialogState extends ConsumerState<_FioDialog> {
  late final TextEditingController _last;
  late final TextEditingController _first;
  late final TextEditingController _patronymic;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _last = TextEditingController(text: widget.patient.lastName);
    _first = TextEditingController(text: widget.patient.firstName);
    _patronymic = TextEditingController(text: widget.patient.patronymic);
  }

  @override
  void dispose() {
    _last.dispose();
    _first.dispose();
    _patronymic.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      await api.updatePatient(
        widget.patient.id,
        lastName: _last.text.trim(),
        firstName: _first.text.trim(),
        patronymic: _patronymic.text.trim(),
      );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } on DioException {
      setState(() => _error = 'Ошибка сохранения');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ФИО пациента'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _last,
              decoration: const InputDecoration(
                labelText: 'Фамилия',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _first,
              decoration: const InputDecoration(
                labelText: 'Имя',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _patronymic,
              decoration: const InputDecoration(
                labelText: 'Отчество',
                border: OutlineInputBorder(),
              ),
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
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(height: 16, width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _AssignmentTile extends ConsumerStatefulWidget {
  final Assignment assignment;
  final VoidCallback onUnassign;

  const _AssignmentTile({required this.assignment, required this.onUnassign});

  @override
  ConsumerState<_AssignmentTile> createState() => _AssignmentTileState();
}

class _AssignmentTileState extends ConsumerState<_AssignmentTile> {
  final _player = WebAudioPlayer();
  int? _playingId;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(int id, String url) async {
    _player.warmup();
    if (_playingId == id) {
      await _player.stopWithFadeOut();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    try {
      await _player.stopWithFadeOut();
      final token = await ref.read(storageProvider).accessToken;
      if (mounted) setState(() => _playingId = id);
      await _player.playWithFadeIn(withAuthToken(url, token));
      if (mounted) setState(() => _playingId = null);
    } catch (_) {
      if (mounted) setState(() => _playingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    final audioAsync = ref.watch(quizAudioProvider(a.quizId));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(a.quizTitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          audioAsync.when(
            data: (audios) {
              if (audios.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('В тесте нет звуков'),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...audios.map((af) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.music_note),
                        title: Text(af.title),
                        trailing: IconButton(
                          icon: Icon(
                            _playingId == af.id ? Icons.stop_circle : Icons.play_circle,
                          ),
                          color: Theme.of(context).colorScheme.primary,
                          onPressed: () => _togglePlay(af.id, af.fileUrl),
                        ),
                      )),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
            error: (_, __) => const Text('Ошибка загрузки звуков'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: a.isCompleted
                ? Chip(
                    label: const Text('Пройден'),
                    backgroundColor: Colors.green[100],
                  )
                : OutlinedButton.icon(
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('Снять'),
                    onPressed: widget.onUnassign,
                  ),
          ),
        ],
      ),
    );
  }
}
