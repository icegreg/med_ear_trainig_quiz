import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/media_auth.dart';
import '../core/web_audio_player.dart';
import '../models/quiz.dart';
import '../providers/auth_provider.dart';
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
              itemBuilder: (context, i) => _QuizTile(quiz: quizzes[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
      ),
    );
  }
}

class _QuizTile extends ConsumerStatefulWidget {
  final QuizSummary quiz;
  const _QuizTile({required this.quiz});

  @override
  ConsumerState<_QuizTile> createState() => _QuizTileState();
}

class _QuizTileState extends ConsumerState<_QuizTile> {
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
    final q = widget.quiz;
    final audioAsync = ref.watch(quizAudioProvider(q.id));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.quiz)),
        title: Text(q.title),
        subtitle: Text(q.description.isNotEmpty
            ? q.description
            : '${q.questionCount} вопросов'),
        trailing: Chip(label: Text('${q.questionCount} вопр.')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        children: [
          audioAsync.when(
            data: (audios) {
              if (audios.isEmpty) {
                return const Text('В тесте нет звуков');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: audios.map((af) => ListTile(
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
                    )).toList(),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('Ошибка загрузки звуков'),
          ),
        ],
      ),
    );
  }
}
