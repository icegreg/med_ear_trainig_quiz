class Patient {
  final int id;
  final String username;
  final String? doctorId;
  final int? startingSoundId;
  final String? startingSoundUrl;
  final DateTime createdAt;

  Patient({
    required this.id,
    required this.username,
    this.doctorId,
    this.startingSoundId,
    this.startingSoundUrl,
    required this.createdAt,
  });

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        id: json['id'],
        username: json['username'],
        doctorId: json['doctor_id'],
        startingSoundId: json['starting_sound_id'],
        startingSoundUrl: json['starting_sound_url'],
        createdAt: DateTime.parse(json['created_at']),
      );
}
