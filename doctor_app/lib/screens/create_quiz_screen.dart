import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/media_auth.dart';
import '../core/web_audio_player.dart';
import '../models/audio_file.dart';
import '../providers/audio_library_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/quiz_provider.dart';

class CreateQuizScreen extends ConsumerStatefulWidget {
  const CreateQuizScreen({super.key});

  @override
  ConsumerState<CreateQuizScreen> createState() => _CreateQuizScreenState();
}

class _CreateQuizScreenState extends ConsumerState<CreateQuizScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _player = WebAudioPlayer();

  /// Выбранные сэмплы в порядке выбора — этот порядок станет порядком вопросов.
  final List<int> _selected = [];
  String _search = '';
  int? _playingId;
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  void _toggle(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _play(AudioFile audio) async {
    _player.warmup();
    if (_playingId == audio.id) {
      await _player.stopWithFadeOut();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    try {
      await _player.stopWithFadeOut();
      final token = await ref.read(storageProvider).accessToken;
      if (mounted) setState(() => _playingId = audio.id);
      await _player.playWithFadeIn(withAuthToken(audio.fileUrl, token));
      if (mounted) setState(() => _playingId = null);
    } catch (_) {
      if (mounted) setState(() => _playingId = null);
    }
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _selected.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.createQuiz(
        title,
        List<int>.from(_selected),
        description: _descCtrl.text.trim(),
      );
      ref.invalidate(quizzesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Тест «$title» создан')),
      );
      context.go('/quizzes');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final msg = (e.response?.data is Map)
          ? e.response!.data['message'] ?? 'Не удалось создать тест'
          : 'Не удалось создать тест';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioAsync = ref.watch(allAudioFilesProvider);
    final canSubmit =
        _titleCtrl.text.trim().isNotEmpty && _selected.isNotEmpty && !_submitting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый тест'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/quizzes'),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _titleCtrl,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Название теста *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Описание (необязательно)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    labelText: 'Поиск звука',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Выбрано: ${_selected.length}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (_selected.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Снять выбор'),
                    onPressed: () => setState(_selected.clear),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: audioAsync.when(
              data: (audioFiles) {
                final filtered = _search.isEmpty
                    ? audioFiles
                    : audioFiles
                        .where((a) => a.title.toLowerCase().contains(_search))
                        .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(audioFiles.isEmpty
                        ? 'В библиотеке нет звуков'
                        : 'Ничего не найдено'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final audio = filtered[i];
                    final order = _selected.indexOf(audio.id);
                    final isSelected = order >= 0;
                    final isPlaying = _playingId == audio.id;
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (_) => _toggle(audio.id),
                      controlAffinity: ListTileControlAffinity.leading,
                      secondary: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected)
                            CircleAvatar(
                              radius: 12,
                              child: Text(
                                '${order + 1}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          IconButton(
                            icon: Icon(
                              isPlaying ? Icons.stop_circle : Icons.play_circle,
                            ),
                            color: Theme.of(context).colorScheme.primary,
                            onPressed: () => _play(audio),
                          ),
                        ],
                      ),
                      title: Text(audio.title),
                      subtitle: Text(audio.durationSeconds != null
                          ? '${audio.durationSeconds} сек'
                          : 'Длительность неизвестна'),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Ошибка: $e')),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_selected.isEmpty
                      ? 'Создать тест'
                      : 'Создать тест (${_selected.length})'),
                  onPressed: canSubmit ? _submit : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
