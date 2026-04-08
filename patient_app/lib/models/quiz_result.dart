class QuizResult {
  final int assignmentId;
  final String quizTitle;
  final List<dynamic> answers;
  final int? score;
  final DateTime submittedAt;

  QuizResult({
    required this.assignmentId,
    required this.quizTitle,
    required this.answers,
    this.score,
    required this.submittedAt,
  });

  factory QuizResult.fromJson(Map<String, dynamic> json) => QuizResult(
        assignmentId: json['assignment_id'],
        quizTitle: json['quiz_title'],
        answers: json['answers'] ?? [],
        score: json['score'],
        submittedAt: DateTime.parse(json['submitted_at']),
      );
}
