class Patient {
  final int id;
  final String username;
  final String? doctorId;
  final DateTime createdAt;

  Patient({
    required this.id,
    required this.username,
    this.doctorId,
    required this.createdAt,
  });

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        id: json['id'],
        username: json['username'],
        doctorId: json['doctor_id'],
        createdAt: DateTime.parse(json['created_at']),
      );
}
