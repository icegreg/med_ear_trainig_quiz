/// Разбор пройденного теста по вопросам: /api/doctors/results/{assignment_id}
class ResultBreakdown {
  final int assignmentId;
  final String quizTitle;
  final DateTime submittedAt;
  final int score;
  final int total;
  final double percent;
  final List<BreakdownItem> questions;

  ResultBreakdown({
    required this.assignmentId,
    required this.quizTitle,
    required this.submittedAt,
    required this.score,
    required this.total,
    required this.percent,
    required this.questions,
  });

  factory ResultBreakdown.fromJson(Map<String, dynamic> json) => ResultBreakdown(
        assignmentId: json['assignment_id'],
        quizTitle: json['quiz_title'] ?? '',
        submittedAt: DateTime.parse(json['submitted_at']),
        score: json['score'] ?? 0,
        total: json['total'] ?? 0,
        percent: (json['percent'] ?? 0).toDouble(),
        questions: (json['questions'] as List? ?? [])
            .map((e) => BreakdownItem.fromJson(e))
            .toList(),
      );
}

/// Одна строка разбора.
class BreakdownItem {
  final int questionId;
  final String text;
  final int? audioId;
  final String? audioTitle;
  final String? audioUrl;
  final bool audioIsDeleted;
  final String patientAnswer;
  final String? correctAnswer;

  /// null — вопрос удалён из квиза, сверять не с чем.
  final bool? isCorrect;
  final bool questionDeleted;

  BreakdownItem({
    required this.questionId,
    required this.text,
    required this.audioId,
    required this.audioTitle,
    required this.audioUrl,
    required this.audioIsDeleted,
    required this.patientAnswer,
    required this.correctAnswer,
    required this.isCorrect,
    required this.questionDeleted,
  });

  factory BreakdownItem.fromJson(Map<String, dynamic> json) => BreakdownItem(
        questionId: json['question_id'] ?? 0,
        text: json['text'] ?? '',
        audioId: json['audio_id'],
        audioTitle: json['audio_title'],
        audioUrl: json['audio_url'],
        audioIsDeleted: json['audio_is_deleted'] ?? false,
        patientAnswer: json['patient_answer'] ?? '',
        correctAnswer: json['correct_answer'],
        isCorrect: json['is_correct'],
        questionDeleted: json['question_deleted'] ?? false,
      );
}
