import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/media_auth.dart';
import '../core/web_audio_player.dart';
import '../models/result_breakdown.dart';
import '../providers/auth_provider.dart';

final resultBreakdownProvider =
    FutureProvider.family<ResultBreakdown, int>((ref, assignmentId) async {
  final api = ref.watch(apiClientProvider);
  return ResultBreakdown.fromJson(await api.getResultBreakdown(assignmentId));
});

/// Ответы пациента хранятся как «да»/«нет», но врачу показываем «Слышу»/«Не слышу».
String answerLabel(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'да':
      return 'Слышу';
    case 'нет':
      return 'Не слышу';
    default:
      return raw ?? '';
  }
}

/// По-вопросный разбор одного пройденного теста: что спросили, что ответил
/// пациент, что было верно. Звук можно прослушать прямо из строки.
class ResultBreakdownView extends ConsumerStatefulWidget {
  final int assignmentId;
  const ResultBreakdownView({super.key, required this.assignmentId});

  @override
  ConsumerState<ResultBreakdownView> createState() =>
      _ResultBreakdownViewState();
}

class _ResultBreakdownViewState extends ConsumerState<ResultBreakdownView> {
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
    final async = ref.watch(resultBreakdownProvider(widget.assignmentId));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('Не удалось загрузить разбор: $e'),
      ),
      data: (breakdown) {
        if (breakdown.questions.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('В этом тесте нет вопросов'),
          );
        }
        return Column(
          key: const Key('result_breakdown'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final q in breakdown.questions)
              _BreakdownRow(
                item: q,
                playing: q.audioId != null && _playingId == q.audioId,
                onPlay: q.audioUrl == null
                    ? null
                    : () => _togglePlay(q.audioId!, q.audioUrl!),
              ),
          ],
        );
      },
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final BreakdownItem item;
  final bool playing;
  final VoidCallback? onPlay;

  const _BreakdownRow({
    required this.item,
    required this.playing,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Верно / ошибка / неизвестно (вопрос удалён) — значок всегда идёт вместе
    // с текстовой подписью ответа, а не заменяет её.
    final (icon, iconColor) = switch (item.isCorrect) {
      true => (Icons.check_circle, Colors.green[700]),
      false => (Icons.cancel, scheme.error),
      null => (Icons.help_outline, scheme.onSurfaceVariant),
    };

    final title = item.audioTitle == null
        ? 'Без звука'
        : (item.audioIsDeleted
            ? '${item.audioTitle} (удалён)'
            : item.audioTitle!);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: item.audioTitle == null || item.audioIsDeleted
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    )),
                const SizedBox(height: 2),
                Text(item.text,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  children: [
                    Text('Ответ: ${answerLabel(item.patientAnswer)}',
                        style: text.bodySmall),
                    // Правильный ответ показываем только когда он отличается —
                    // иначе это шум на каждой верной строке.
                    if (item.isCorrect == false && item.correctAnswer != null)
                      Text('Верно: ${answerLabel(item.correctAnswer)}',
                          style: text.bodySmall?.copyWith(color: scheme.error)),
                    if (item.isCorrect == null)
                      Text('Вопрос удалён — сверить не с чем',
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          if (onPlay != null)
            IconButton(
              tooltip: 'Прослушать звук',
              icon: Icon(playing ? Icons.stop_circle : Icons.play_circle),
              color: scheme.primary,
              onPressed: onPlay,
            ),
        ],
      ),
    );
  }
}
