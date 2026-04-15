class Assignment {
  final int id;
  final int quizId;
  final String quizTitle;
  final String status;
  final DateTime assignedAt;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? completedAt;

  Assignment({
    required this.id,
    required this.quizId,
    required this.quizTitle,
    required this.status,
    required this.assignedAt,
    this.startsAt,
    this.endsAt,
    this.completedAt,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) => Assignment(
        id: json['id'],
        quizId: json['quiz_id'],
        quizTitle: json['quiz_title'],
        status: json['status'],
        assignedAt: DateTime.parse(json['assigned_at']),
        startsAt: json['starts_at'] != null ? DateTime.parse(json['starts_at']) : null,
        endsAt: json['ends_at'] != null ? DateTime.parse(json['ends_at']) : null,
        completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
      );

  bool get isCompleted => status == 'completed';
}
