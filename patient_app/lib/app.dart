import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/storage.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/lock_provider.dart';
import 'providers/settings_provider.dart';
import 'router.dart';
import 'screens/lock_screen.dart';

class PatientApp extends ConsumerStatefulWidget {
  const PatientApp({super.key});

  @override
  ConsumerState<PatientApp> createState() => _PatientAppState();
}

class _PatientAppState extends ConsumerState<PatientApp>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pausedAt = DateTime.now();
      _idleTimer?.cancel(); // в фоне простой не считаем
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt != null &&
          DateTime.now().difference(pausedAt) >= kAutoLockTimeout) {
        ref.read(lockProvider.notifier).lock();
      }
      _restartIdleTimer();
    }
  }

  /// Любое действие пользователя сбрасывает таймер простоя.
  void _onUserActivity() => _restartIdleTimer();

  /// Перезапускает отсчёт простоя; тикает только пока пользователь залогинен
  /// и приложение не заблокировано.
  void _restartIdleTimer() {
    _idleTimer?.cancel();
    final authed =
        ref.read(authProvider).status == AuthStatus.authenticated;
    final locked = ref.read(lockProvider);
    if (!authed || locked) return;
    _idleTimer = Timer(kIdleLockTimeout, () {
      if (!mounted) return;
      final stillAuthed =
          ref.read(authProvider).status == AuthStatus.authenticated;
      if (stillAuthed && !ref.read(lockProvider)) {
        ref.read(lockProvider.notifier).lock();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(darkModeProvider);
    final router = ref.watch(routerProvider);
    final locked = ref.watch(lockProvider);
    final hasPin = ref.watch(storageProvider).hasPin;

    // Изменение авторизации/блокировки пересчитывает таймер простоя.
    ref.listen(authProvider, (_, __) => _restartIdleTimer());
    ref.listen(lockProvider, (_, __) => _restartIdleTimer());

    return MaterialApp.router(
      title: 'TNOISE',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      builder: (context, child) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _onUserActivity(),
          onPointerMove: (_) => _onUserActivity(),
          onPointerSignal: (_) => _onUserActivity(),
          child: Stack(
            children: [
              if (child != null) child,
              // PIN-блокировка как оверлей: низлежащий экран остаётся
              // смонтированным, поэтому при разблокировке мы возвращаемся
              // ровно в то же состояние.
              if (locked && hasPin) const Positioned.fill(child: LockScreen()),
            ],
          ),
        );
      },
    );
  }
}
