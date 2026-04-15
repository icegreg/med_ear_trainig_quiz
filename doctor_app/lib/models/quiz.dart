class QuizSummary {
  final int id;
  final String title;
  final String description;
  final int questionCount;
  final DateTime createdAt;

  QuizSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.questionCount,
    required this.createdAt,
  });

  factory QuizSummary.fromJson(Map<String, dynamic> json) => QuizSummary(
        id: json['id'],
        title: json['title'],
        description: json['description'] ?? '',
        questionCount: json['question_count'],
        createdAt: DateTime.parse(json['created_at']),
      );
}
