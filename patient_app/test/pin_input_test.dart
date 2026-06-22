import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/widgets/pin_input.dart';

/// Юнит-тесты цифровой клавиатуры PinInput (без платформенных каналов).
///
/// Запуск: flutter test test/pin_input_test.dart
void main() {
  Widget harness({
    required String value,
    required ValueChanged<String> onChanged,
    required ValueChanged<String> onCompleted,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: PinInput(
            value: value,
            onChanged: onChanged,
            onCompleted: onCompleted,
          ),
        ),
      );

  testWidgets('нажатие цифры сообщает новое значение', (tester) async {
    String? changed;
    await tester.pumpWidget(harness(
      value: '',
      onChanged: (v) => changed = v,
      onCompleted: (_) {},
    ));

    await tester.tap(find.widgetWithText(OutlinedButton, '7'));
    expect(changed, '7');
  });

  testWidgets('четвёртая цифра вызывает onCompleted с полным кодом',
      (tester) async {
    String? completed;
    await tester.pumpWidget(harness(
      value: '123',
      onChanged: (_) {},
      onCompleted: (v) => completed = v,
    ));

    await tester.tap(find.widgetWithText(OutlinedButton, '4'));
    expect(completed, '1234');
  });

  testWidgets('backspace убирает последнюю цифру', (tester) async {
    String? changed;
    await tester.pumpWidget(harness(
      value: '12',
      onChanged: (v) => changed = v,
      onCompleted: (_) {},
    ));

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    expect(changed, '1');
  });

  testWidgets('ввод сверх длины кода игнорируется', (tester) async {
    var changedCalled = false;
    var completedCalled = false;
    await tester.pumpWidget(harness(
      value: '1234',
      onChanged: (_) => changedCalled = true,
      onCompleted: (_) => completedCalled = true,
    ));

    await tester.tap(find.widgetWithText(OutlinedButton, '5'));
    expect(changedCalled, isFalse);
    expect(completedCalled, isFalse);
  });
}
