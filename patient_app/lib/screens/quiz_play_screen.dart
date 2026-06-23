import 'dart:async';
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

  /// Кнопки ответа активны только после окончания звука или по таймауту.
  bool _canAnswer = false;
  Timer? _enableTimer;

  /// Сколько максимум ждём активации кнопок, если звук длиннее.
  static const _maxWaitBeforeAnswer = Duration(seconds: 5);

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
    final index = _currentIndex;
    final question = _quiz!.questions[index];

    // Новый вопрос — снова блокируем ответ, пока звук не доиграет / не пройдёт таймаут.
    _enableTimer?.cancel();
    setState(() {
      _canAnswer = false;
      _audioPlaying = false;
    });

    final cache = ref.read(audioCacheProvider.notifier);
    final audioBytes =
        question.audioFileId == null ? null : cache.getFile(question.audioFileId!);

    // Нет звука для проигрывания — отвечать можно сразу.
    if (audioBytes == null) {
      if (mounted) setState(() => _canAnswer = true);
      return;
    }

    // Активируем кнопки по таймауту, если звук окажется длиннее 5 секунд.
    _enableTimer = Timer(_maxWaitBeforeAnswer, () {
      if (mounted && _currentIndex == index) setState(() => _canAnswer = true);
    });

    try {
      setState(() => _audioPlaying = true);
      await _player.setAudioSource(_BytesAudioSource(audioBytes));
      await _player.play(); // завершается, когда звук доиграл
      if (mounted && _currentIndex == index) {
        _enableTimer?.cancel();
        setState(() {
          _audioPlaying = false;
          _canAnswer = true;
        });
      }
    } catch (_) {
      // Ошибку воспроизведения не превращаем в тупик — разрешаем ответить.
      if (mounted && _currentIndex == index) {
        _enableTimer?.cancel();
        setState(() {
          _audioPlaying = false;
          _canAnswer = true;
        });
      }
    }
  }

  void _answer(String answer) {
    if (_quiz == null || _submitting || !_canAnswer) return;
    _enableTimer?.cancel();
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
    _enableTimer?.cancel();
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Text(
                _quiz!.title,
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Звук ${_currentIndex + 1} из $total',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
                child: SizedBox(
                  height: 240,
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _canAnswer ? () => _answer('да') : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: const Text('Слышу',
                              style: TextStyle(
                                  fontSize: 32, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: _canAnswer ? () => _answer('нет') : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: const Text('Не слышу',
                              style: TextStyle(
                                  fontSize: 32, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
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
