class QuizListItem {
  final int id;
  final String title;
  final String description;
  final String status;
  final DateTime assignedAt;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isAvailable;
  final bool isUpcoming;
  final bool isExpired;
  final int? daysUntilDeadline;

  QuizListItem({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.assignedAt,
    this.startsAt,
    this.endsAt,
    required this.isAvailable,
    required this.isUpcoming,
    required this.isExpired,
    this.daysUntilDeadline,
  });

  bool get isCompleted => status == 'completed';

  /// Дедлайн скоро (3 дня или меньше)
  bool get isDeadlineSoon =>
      daysUntilDeadline != null && daysUntilDeadline! <= 3 && isAvailable;

  factory QuizListItem.fromJson(Map<String, dynamic> json) => QuizListItem(
        id: json['id'],
        title: json['title'],
        description: json['description'] ?? '',
        status: json['status'],
        assignedAt: DateTime.parse(json['assigned_at']),
        startsAt: json['starts_at'] != null
            ? DateTime.parse(json['starts_at'])
            : null,
        endsAt: json['ends_at'] != null
            ? DateTime.parse(json['ends_at'])
            : null,
        isAvailable: json['is_available'] ?? true,
        isUpcoming: json['is_upcoming'] ?? false,
        isExpired: json['is_expired'] ?? false,
        daysUntilDeadline: json['days_until_deadline'],
      );
}

class QuizDetail {
  final int id;
  final String title;
  final String description;
  final List<QuizQuestion> questions;
  final List<int> audioFileIds;

  QuizDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.questions,
    required this.audioFileIds,
  });

  factory QuizDetail.fromJson(Map<String, dynamic> json) => QuizDetail(
        id: json['id'],
        title: json['title'],
        description: json['description'] ?? '',
        questions: (json['questions'] as List)
            .map((q) => QuizQuestion.fromJson(q))
            .toList(),
        audioFileIds: List<int>.from(json['audio_file_ids'] ?? []),
      );
}

class QuizQuestion {
  final int id;
  final int? audioFileId;
  final String text;
  final List<String> options;
  final int order;

  QuizQuestion({
    required this.id,
    this.audioFileId,
    required this.text,
    required this.options,
    required this.order,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
        id: json['id'],
        audioFileId: json['audio_file_id'],
        text: json['text'],
        options: List<String>.from(json['options'] ?? ['да', 'нет']),
        order: json['order'],
      );
}
