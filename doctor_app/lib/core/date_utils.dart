int ageInYears(DateTime birthDate, {DateTime? now}) {
  final today = now ?? DateTime.now();
  int age = today.year - birthDate.year;
  if (today.month < birthDate.month ||
      (today.month == birthDate.month && today.day < birthDate.day)) {
    age--;
  }
  return age;
}

String pluralYears(int n) {
  final mod100 = n.abs() % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'лет';
  switch (n.abs() % 10) {
    case 1:
      return 'год';
    case 2:
    case 3:
    case 4:
      return 'года';
    default:
      return 'лет';
  }
}

String formatAge(DateTime birthDate, {DateTime? now}) {
  final years = ageInYears(birthDate, now: now);
  return '$years ${pluralYears(years)}';
}
