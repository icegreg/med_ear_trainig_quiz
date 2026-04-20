class Patient {
  final int id;
  final String username;
  final String? doctorId;
  final String lastName;
  final String firstName;
  final String patronymic;
  final String fullName;
  final int? startingSoundId;
  final String? startingSoundUrl;
  final DateTime? birthDate;
  final int assignedCount;
  final int completedCount;
  final DateTime createdAt;

  Patient({
    required this.id,
    required this.username,
    this.doctorId,
    this.lastName = '',
    this.firstName = '',
    this.patronymic = '',
    this.fullName = '',
    this.startingSoundId,
    this.startingSoundUrl,
    this.birthDate,
    this.assignedCount = 0,
    this.completedCount = 0,
    required this.createdAt,
  });

  String get displayName => fullName.isNotEmpty ? fullName : username;

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        id: json['id'],
        username: json['username'],
        doctorId: json['doctor_id'],
        lastName: json['last_name'] ?? '',
        firstName: json['first_name'] ?? '',
        patronymic: json['patronymic'] ?? '',
        fullName: json['full_name'] ?? '',
        startingSoundId: json['starting_sound_id'],
        startingSoundUrl: json['starting_sound_url'],
        birthDate: json['birth_date'] != null
            ? DateTime.parse(json['birth_date'])
            : null,
        assignedCount: json['assigned_count'] ?? 0,
        completedCount: json['completed_count'] ?? 0,
        createdAt: DateTime.parse(json['created_at']),
      );
}
