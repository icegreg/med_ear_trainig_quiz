import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:volume_controller/volume_controller.dart';

import '../core/audio_cache.dart';
import '../core/storage.dart';
import '../providers/patient_provider.dart';

class QuizPrepScreen extends ConsumerStatefulWidget {
  final int quizId;
  const QuizPrepScreen({super.key, required this.quizId});

  @override
  ConsumerState<QuizPrepScreen> createState() => _QuizPrepScreenState();
}

class _QuizPrepScreenState extends ConsumerState<QuizPrepScreen> {
  int _batteryLevel = -1;
  bool _batteryChecked = false;
  bool _volumeSet = false;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _checkBattery();
    _setVolume();
    _startDownload();
  }

  Future<void> _checkBattery() async {
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;
      if (mounted) {
        setState(() {
          _batteryLevel = level;
          _batteryChecked = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _batteryLevel = 100;
          _batteryChecked = true;
        });
      }
    }
  }

  Future<void> _setVolume() async {
    try {
      final storage = ref.read(storageProvider);
      final volume = storage.volumeLevel;
      await VolumeController.instance.setVolume(volume);
    } catch (_) {}
    if (mounted) setState(() => _volumeSet = true);
  }

  Future<void> _startDownload() async {
    setState(() => _downloadError = null);
    try {
      await ref.read(audioCacheProvider.notifier).downloadForQuiz(widget.quizId);
    } catch (e) {
      if (mounted) {
        setState(() => _downloadError = 'Ошибка загрузки аудио');
      }
    }
  }

  Future<void> _startQuiz(BuildContext context) async {
    // Воспроизвести стартовый звук, если назначен
    try {
      final patient = await ref.read(patientProvider.future);
      if (patient.startingSoundUrl != null) {
        final player = AudioPlayer();
        try {
          await player.setUrl(patient.startingSoundUrl!);
          await player.play();
          await player.playerStateStream.firstWhere(
            (s) => s.processingState == ProcessingState.completed,
          );
        } finally {
          await player.dispose();
        }
      }
    } catch (_) {
      // Не блокируем тест при ошибке воспроизведения стартового звука
    }
    if (mounted) {
      context.pushReplacement('/quiz/${widget.quizId}/play');
    }
  }

  bool get _batteryOk {
    final threshold = ref.read(storageProvider).batteryThreshold;
    return _batteryLevel >= threshold;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audioCache = ref.watch(audioCacheProvider);
    final allReady =
        _batteryChecked && _batteryOk && _volumeSet && audioCache.isReady;

    return Scaffold(
      appBar: AppBar(title: const Text('Подготовка')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            _CheckItem(
              icon: Icons.battery_charging_full,
              title: 'Заряд батареи',
              subtitle: _batteryChecked ? '$_batteryLevel%' : 'Проверка...',
              status: !_batteryChecked
                  ? _CheckStatus.loading
                  : _batteryOk
                      ? _CheckStatus.ok
                      : _CheckStatus.error,
            ),
            const SizedBox(height: 16),
            _CheckItem(
              icon: Icons.volume_up,
              title: 'Громкость',
              subtitle: _volumeSet ? 'Установлена' : 'Настройка...',
              status: _volumeSet ? _CheckStatus.ok : _CheckStatus.loading,
            ),
            const SizedBox(height: 16),
            // Аудио-файлы с прогрессом
            _AudioDownloadItem(
              audioCache: audioCache,
              error: _downloadError,
            ),
            const Spacer(),
            if (_batteryChecked && !_batteryOk)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Недостаточный заряд батареи. '
                  'Подключите зарядное устройство.',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_downloadError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton.icon(
                  onPressed: _startDownload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Повторить загрузку'),
                ),
              ),
            ElevatedButton(
              onPressed: allReady
                  ? () => _startQuiz(context)
                  : null,
              child: const Text('Начать тест'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

enum _CheckStatus { loading, ok, error }

class _CheckItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final _CheckStatus status;

  const _CheckItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            switch (status) {
              _CheckStatus.loading => const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              _CheckStatus.ok =>
                const Icon(Icons.check_circle, color: Colors.green, size: 28),
              _CheckStatus.error =>
                Icon(Icons.error, color: theme.colorScheme.error, size: 28),
            },
          ],
        ),
      ),
    );
  }
}

class _AudioDownloadItem extends StatelessWidget {
  final AudioCacheState audioCache;
  final String? error;

  const _AudioDownloadItem({required this.audioCache, this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final String subtitle;
    final Widget trailing;

    if (error != null) {
      subtitle = error!;
      trailing = Icon(Icons.error, color: theme.colorScheme.error, size: 28);
    } else if (audioCache.isReady) {
      subtitle = '${audioCache.files.length} файлов загружено';
      trailing =
          const Icon(Icons.check_circle, color: Colors.green, size: 28);
    } else {
      subtitle = audioCache.statusText ?? 'Подготовка...';
      trailing = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.download, size: 36, color: theme.colorScheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Аудио-файлы',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(subtitle, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
            if (audioCache.downloadProgress != null && !audioCache.isReady && error == null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: audioCache.downloadProgress,
                  minHeight: 8,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
