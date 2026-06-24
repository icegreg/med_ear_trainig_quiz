import 'audio_file.dart';

class QuizSummary {
  final int id;
  final String title;
  final String description;
  final int questionCount;
  final DateTime createdAt;

  /// Аудио теста приходит сразу в списке тестов (без отдельного /audio).
  final List<AudioFile> audioFiles;

  QuizSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.questionCount,
    required this.createdAt,
    this.audioFiles = const [],
  });

  factory QuizSummary.fromJson(Map<String, dynamic> json) => QuizSummary(
        id: json['id'],
        title: json['title'],
        description: json['description'] ?? '',
        questionCount: json['question_count'],
        createdAt: DateTime.parse(json['created_at']),
        audioFiles: ((json['audio_files'] as List?) ?? [])
            .map((e) => AudioFile.fromJson(e))
            .toList(),
      );
}
