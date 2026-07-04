import 'dart:math';

const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _lower = 'abcdefghijklmnopqrstuvwxyz';
const _digits = '0123456789';

/// Случайный пароль: [length] символов из латиницы (обоих регистров) и цифр,
/// гарантированно с хотя бы одной заглавной, строчной и цифрой.
String generatePassword({int length = 12}) {
  final rng = Random.secure();
  const all = _upper + _lower + _digits;
  final chars = <String>[
    _upper[rng.nextInt(_upper.length)],
    _lower[rng.nextInt(_lower.length)],
    _digits[rng.nextInt(_digits.length)],
  ];
  for (var i = chars.length; i < length; i++) {
    chars.add(all[rng.nextInt(all.length)]);
  }
  chars.shuffle(rng);
  return chars.join();
}
