import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/storage.dart';
import '../providers/auth_provider.dart';
import '../providers/lock_provider.dart';
import '../widgets/pin_input.dart';

/// Оверлей быстрого входа по ПИН-коду (показывается поверх текущего экрана,
/// когда токен жив, но приложение заблокировано и установлен код доступа).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _value = '';
  bool _error = false;
  int _attempts = 0;

  void _onCompleted(String pin) {
    final storage = ref.read(storageProvider);
    if (storage.verifyPin(pin)) {
      // Снимаем оверлей — низлежащий экран остаётся в прежнем состоянии.
      ref.read(lockProvider.notifier).unlock();
      return;
    }

    _attempts++;
    if (_attempts >= kMaxPinAttempts) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Слишком много попыток. Войдите по паролю.'),
        ),
      );
      _fallbackToPassword();
      return;
    }

    setState(() {
      _error = true;
      _value = '';
    });
  }

  /// Забыл код — полный выход, чтобы войти по паролю (редирект на /login
  /// произойдёт автоматически после сброса авторизации).
  void _fallbackToPassword() {
    ref.read(authProvider.notifier).logout();
    ref.read(lockProvider.notifier).unlock();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline,
                    size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('Введите код доступа',
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  _error
                      ? 'Неверный код. Осталось попыток: '
                          '${kMaxPinAttempts - _attempts}'
                      : 'Для быстрого входа',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _error
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                PinInput(
                  value: _value,
                  error: _error,
                  onChanged: (v) => setState(() {
                    _value = v;
                    _error = false;
                  }),
                  onCompleted: _onCompleted,
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _fallbackToPassword,
                  child: const Text('Забыли код? Войти по паролю'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
