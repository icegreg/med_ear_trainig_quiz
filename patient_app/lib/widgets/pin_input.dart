import 'package:flutter/material.dart';

import '../core/constants.dart';

/// Индикатор введённых цифр (точки) + цифровая клавиатура.
///
/// Управляется снаружи через [value]; сообщает об изменениях через
/// [onChanged] и о вводе полного кода через [onCompleted].
class PinInput extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted;
  final bool error;

  const PinInput({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onCompleted,
    this.error = false,
  });

  void _press(String digit) {
    if (value.length >= kPinLength) return;
    final next = value + digit;
    onChanged(next);
    if (next.length == kPinLength) onCompleted(next);
  }

  void _backspace() {
    if (value.isEmpty) return;
    onChanged(value.substring(0, value.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = error ? theme.colorScheme.error : theme.colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(kPinLength, (i) {
            final filled = i < value.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? activeColor : Colors.transparent,
                border: Border.all(color: activeColor, width: 2),
              ),
            );
          }),
        ),
        const SizedBox(height: 40),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) _DigitButton(d, () => _press(d))],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 88),
            _DigitButton('0', () => _press('0')),
            SizedBox(
              width: 88,
              height: 88,
              child: IconButton(
                icon: const Icon(Icons.backspace_outlined, size: 28),
                onPressed: _backspace,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DigitButton extends StatelessWidget {
  final String digit;
  final VoidCallback onPressed;

  const _DigitButton(this.digit, this.onPressed);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 72,
        height: 72,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
          ),
          child: Text(
            digit,
            style: theme.textTheme.headlineMedium,
          ),
        ),
      ),
    );
  }
}
