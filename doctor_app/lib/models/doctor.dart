class Doctor {
  final String id;
  final String lastName;
  final String firstName;
  final String patronymic;
  final String clinic;
  final DateTime createdAt;

  Doctor({
    required this.id,
    required this.lastName,
    required this.firstName,
    required this.patronymic,
    required this.clinic,
    required this.createdAt,
  });

  factory Doctor.fromJson(Map<String, dynamic> json) => Doctor(
        id: json['id'],
        lastName: json['last_name'] ?? '',
        firstName: json['first_name'] ?? '',
        patronymic: json['patronymic'] ?? '',
        clinic: json['clinic'] ?? '',
        createdAt: DateTime.parse(json['created_at']),
      );

  String get fullName {
    final parts = [lastName, firstName];
    if (patronymic.isNotEmpty) parts.add(patronymic);
    return parts.join(' ');
  }
}

class DoctorListItem {
  final String id;
  final String lastName;
  final String firstName;
  final String patronymic;
  final String clinic;

  DoctorListItem({
    required this.id,
    required this.lastName,
    required this.firstName,
    required this.patronymic,
    required this.clinic,
  });

  factory DoctorListItem.fromJson(Map<String, dynamic> json) => DoctorListItem(
        id: json['id'],
        lastName: json['last_name'] ?? '',
        firstName: json['first_name'] ?? '',
        patronymic: json['patronymic'] ?? '',
        clinic: json['clinic'] ?? '',
      );

  String get fullName {
    final parts = [lastName, firstName];
    if (patronymic.isNotEmpty) parts.add(patronymic);
    return parts.join(' ');
  }
}
