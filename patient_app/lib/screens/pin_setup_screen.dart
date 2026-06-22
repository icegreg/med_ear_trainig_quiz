import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/storage.dart';
import '../widgets/pin_input.dart';

/// Создание/смена кода быстрого входа.
///
/// Открывается после первого входа (как предложение) и из настроек.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String _value = '';
  String? _firstEntry;
  bool _error = false;

  bool get _confirming => _firstEntry != null;

  void _onCompleted(String pin) async {
    if (!_confirming) {
      setState(() {
        _firstEntry = pin;
        _value = '';
        _error = false;
      });
      return;
    }

    if (pin != _firstEntry) {
      setState(() {
        _firstEntry = null;
        _value = '';
        _error = true;
      });
      return;
    }

    await ref.read(storageProvider).setPin(pin);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Код доступа сохранён')),
    );
    _finish();
  }

  void _finish() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Код быстрого входа'),
        actions: [
          TextButton(
            onPressed: _finish,
            child: const Text('Позже'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pin_outlined,
                    size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  _confirming ? 'Повторите код' : 'Придумайте код',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _error
                      ? 'Коды не совпали, попробуйте снова'
                      : 'Он понадобится для быстрого входа без пароля',
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
