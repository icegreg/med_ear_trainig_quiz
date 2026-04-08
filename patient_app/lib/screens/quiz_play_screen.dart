import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../core/api_client.dart';
import '../core/audio_cache.dart';
import '../models/quiz.dart';
import '../providers/quiz_provider.dart';

class QuizPlayScreen extends ConsumerStatefulWidget {
  final int quizId;
  const QuizPlayScreen({super.key, required this.quizId});

  @override
  ConsumerState<QuizPlayScreen> createState() => _QuizPlayScreenState();
}

class _QuizPlayScreenState extends ConsumerState<QuizPlayScreen> {
  final _player = AudioPlayer();
  int _currentIndex = 0;
  final List<Map<String, dynamic>> _answers = [];
  bool _submitting = false;
  bool _audioPlaying = false;

  QuizDetail? _quiz;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  Future<void> _loadQuiz() async {
    final quiz = await ref.read(quizDetailProvider(widget.quizId).future);
    if (mounted) {
      setState(() => _quiz = quiz);
      _playCurrentAudio();
    }
  }

  Future<void> _playCurrentAudio() async {
    if (_quiz == null) return;
    final question = _quiz!.questions[_currentIndex];
    if (question.audioFileId == null) return;

    final cache = ref.read(audioCacheProvider.notifier);
    final audioBytes = cache.getFile(question.audioFileId!);

    if (audioBytes == null) return;

    try {
      setState(() => _audioPlaying = true);
      await _player.setAudioSource(
        _BytesAudioSource(audioBytes),
      );
      await _player.play();
      if (mounted) setState(() => _audioPlaying = false);
    } catch (_) {
      if (mounted) setState(() => _audioPlaying = false);
    }
  }

  void _answer(String answer) {
    if (_quiz == null || _submitting) return;
    final question = _quiz!.questions[_currentIndex];

    _answers.add({
      'question_id': question.id,
      'answer': answer,
    });

    if (_currentIndex < _quiz!.questions.length - 1) {
      setState(() => _currentIndex++);
      _playCurrentAudio();
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.submitQuiz(widget.quizId, _answers);
      ref.invalidate(quizListProvider);
      ref.read(audioCacheProvider.notifier).clear();
      if (mounted) context.pushReplacement('/quiz/done');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка отправки. Попробуйте ещё раз.')),
        );
        setState(() => _submitting = false);
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_quiz == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final total = _quiz!.questions.length;
    final question = _quiz!.questions[_currentIndex];
    final progress = (_currentIndex + 1) / total;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: progress, minHeight: 6),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Вопрос ${_currentIndex + 1} из $total',
                style: theme.textTheme.headlineMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                question.text,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            if (_audioPlaying)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.volume_up,
                        color: theme.colorScheme.primary, size: 32),
                    const SizedBox(width: 8),
                    Text('Воспроизведение...',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: theme.colorScheme.primary)),
                  ],
                ),
              ),
            const Spacer(),
            if (_submitting)
              const Center(child: CircularProgressIndicator())
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 120,
                      child: FilledButton(
                        onPressed: () => _answer('да'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('ДА',
                            style: TextStyle(
                                fontSize: 36, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 120,
                      child: FilledButton(
                        onPressed: () => _answer('нет'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('НЕТ',
                            style: TextStyle(
                                fontSize: 36, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// AudioSource из bytes в памяти (для web и кэшированных файлов).
class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;

  _BytesAudioSource(this._bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream.value(_bytes.sublist(s, e)),
      contentType: 'audio/wav',
    );
  }
}
