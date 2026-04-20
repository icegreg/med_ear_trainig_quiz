import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Плеер на Web Audio API: fetch → decodeAudioData → AudioBufferSource → GainNode → destination.
/// Fade через GainAudioParam.linearRampToValueAtTime — sample-accurate, без щелчков.
///
/// warmup() должен вызываться СИНХРОННО в обработчике клика (до await-ов).
class WebAudioPlayer {
  web.AudioContext? _ctx;
  web.GainNode? _gain;
  web.AudioBufferSourceNode? _currentSource;
  final Map<String, web.AudioBuffer> _cache = {};
  Completer<void>? _playCompleter;
  bool _unlocked = false;

  static const _fadeSeconds = 0.08;

  void _init() {
    if (_ctx != null) return;
    _ctx = web.AudioContext();
    _gain = _ctx!.createGain();
    _gain!.connect(_ctx!.destination);
    _gain!.gain.value = 0;
  }

  /// Принудительный перевод контекста в 'running' через проигрывание тишины
  /// — iOS Safari / Chrome требуют user-gesture unlock.
  void _unlockOnce() {
    if (_unlocked) return;
    try {
      final buffer = _ctx!.createBuffer(1, 1, 22050);
      final src = _ctx!.createBufferSource();
      src.buffer = buffer;
      src.connect(_ctx!.destination);
      src.start();
      _unlocked = true;
    } catch (_) {}
  }

  /// Вызывать СИНХРОННО в обработчике клика, до await-ов.
  void warmup() {
    _init();
    _unlockOnce();
    if (_ctx!.state == 'suspended') {
      _ctx!.resume();
    }
  }

  Future<void> _waitRunning({int maxMs = 1500}) async {
    if (_ctx!.state == 'running') return;
    try {
      await _ctx!.resume().toDart;
    } catch (_) {}
    final sw = Stopwatch()..start();
    while (_ctx!.state != 'running' && sw.elapsedMilliseconds < maxMs) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<web.AudioBuffer> _loadBuffer(String url) async {
    final cached = _cache[url];
    if (cached != null) return cached;
    final resp = await web.window.fetch(url.toJS).toDart;
    if (!resp.ok) {
      throw Exception('Failed to load audio: HTTP ${resp.status}');
    }
    final ab = await resp.arrayBuffer().toDart;
    final buffer = await _ctx!.decodeAudioData(ab).toDart;
    _cache[url] = buffer;
    return buffer;
  }

  void _completePlay() {
    final c = _playCompleter;
    if (c != null && !c.isCompleted) c.complete();
    _playCompleter = null;
    _currentSource = null;
  }

  Future<void> playWithFadeIn(String url) async {
    _init();
    _unlockOnce();
    await _waitRunning();

    final buffer = await _loadBuffer(url);

    // Остановить текущий, если есть.
    try {
      _currentSource?.stop();
    } catch (_) {}
    _completePlay();

    final src = _ctx!.createBufferSource();
    src.buffer = buffer;
    src.connect(_gain!);
    src.addEventListener('ended', ((web.Event _) => _completePlay()).toJS);

    final now = _ctx!.currentTime;
    _gain!.gain.cancelScheduledValues(now);
    _gain!.gain.setValueAtTime(0, now);
    _gain!.gain.linearRampToValueAtTime(1.0, now + _fadeSeconds);

    _playCompleter = Completer<void>();
    _currentSource = src;
    src.start();

    await _playCompleter!.future;
  }

  Future<void> stopWithFadeOut() async {
    if (_playCompleter == null || _ctx == null) return;
    final now = _ctx!.currentTime;
    final g = _gain!.gain;
    g.cancelScheduledValues(now);
    g.setValueAtTime(g.value, now);
    g.linearRampToValueAtTime(0, now + _fadeSeconds);
    await Future.delayed(
      Duration(milliseconds: (_fadeSeconds * 1000).round() + 20),
    );
    try {
      _currentSource?.stop();
    } catch (_) {}
    _completePlay();
  }

  void dispose() {
    try {
      _currentSource?.stop();
    } catch (_) {}
    _completePlay();
    try {
      _ctx?.close();
    } catch (_) {}
  }
}
