/// Агрегат статистики пациента: /api/doctors/patients/{id}/stats
class PatientStats {
  final List<StatsPoint> dynamics;
  final List<SoundError> soundErrors;
  final Adherence adherence;
  final Activity activity;

  PatientStats({
    required this.dynamics,
    required this.soundErrors,
    required this.adherence,
    required this.activity,
  });

  bool get isEmpty => dynamics.isEmpty && soundErrors.isEmpty;

  factory PatientStats.fromJson(Map<String, dynamic> json) => PatientStats(
        dynamics: (json['dynamics'] as List? ?? [])
            .map((e) => StatsPoint.fromJson(e))
            .toList(),
        soundErrors: (json['sound_errors'] as List? ?? [])
            .map((e) => SoundError.fromJson(e))
            .toList(),
        adherence: Adherence.fromJson(json['adherence'] ?? const {}),
        activity: Activity.fromJson(json['activity'] ?? const {}),
      );
}

/// Один пройденный тест — точка на графике динамики.
class StatsPoint {
  final int assignmentId;
  final String quizTitle;
  final int score;
  final int total;
  final double percent;
  final DateTime submittedAt;

  StatsPoint({
    required this.assignmentId,
    required this.quizTitle,
    required this.score,
    required this.total,
    required this.percent,
    required this.submittedAt,
  });

  factory StatsPoint.fromJson(Map<String, dynamic> json) => StatsPoint(
        assignmentId: json['assignment_id'],
        quizTitle: json['quiz_title'] ?? '',
        score: json['score'] ?? 0,
        total: json['total'] ?? 0,
        percent: (json['percent'] ?? 0).toDouble(),
        submittedAt: DateTime.parse(json['submitted_at']),
      );
}

/// Ошибки по одному звуку, агрегированные по всем тестам пациента.
class SoundError {
  final int? audioId;
  final String title;
  final String? category;
  final int answered;
  final int errors;
  final double errorPercent;
  final bool isDeleted;

  SoundError({
    required this.audioId,
    required this.title,
    required this.category,
    required this.answered,
    required this.errors,
    required this.errorPercent,
    required this.isDeleted,
  });

  factory SoundError.fromJson(Map<String, dynamic> json) => SoundError(
        audioId: json['audio_id'],
        title: json['title'] ?? '',
        category: json['category'],
        answered: json['answered'] ?? 0,
        errors: json['errors'] ?? 0,
        errorPercent: (json['error_percent'] ?? 0).toDouble(),
        isDeleted: json['is_deleted'] ?? false,
      );
}

/// Календарь активности: дни, когда пациент сдавал тесты, и последний вход.
class Activity {
  final List<ActivityDay> days;

  /// Последний выход приложения на сервер. История заходов не хранится —
  /// на сервере это одна отметка на устройство, поэтому только дата.
  final DateTime? lastSeenAt;

  Activity({required this.days, this.lastSeenAt});

  /// Тесты по дате (локальной дате сервера) — для быстрого поиска в heatmap.
  Map<DateTime, int> get byDate => {
        for (final d in days) d.date: d.quizzes,
      };

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
        days: (json['days'] as List? ?? [])
            .map((e) => ActivityDay.fromJson(e))
            .toList(),
        lastSeenAt: json['last_seen_at'] == null
            ? null
            : DateTime.parse(json['last_seen_at']),
      );
}

/// Один день календаря: сколько тестов сдано.
class ActivityDay {
  final DateTime date;
  final int quizzes;

  ActivityDay({required this.date, required this.quizzes});

  factory ActivityDay.fromJson(Map<String, dynamic> json) => ActivityDay(
        date: DateTime.parse(json['date']),
        quizzes: json['quizzes'] ?? 0,
      );
}

/// Приверженность: назначено / пройдено / просрочено и скорость прохождения.
class Adherence {
  final int assigned;
  final int completed;
  final int expired;
  final int upcoming;
  final List<int> completionLagDays;
  final double? avgCompletionDays;

  Adherence({
    required this.assigned,
    required this.completed,
    required this.expired,
    required this.upcoming,
    required this.completionLagDays,
    this.avgCompletionDays,
  });

  factory Adherence.fromJson(Map<String, dynamic> json) => Adherence(
        assigned: json['assigned'] ?? 0,
        completed: json['completed'] ?? 0,
        expired: json['expired'] ?? 0,
        upcoming: json['upcoming'] ?? 0,
        completionLagDays:
            (json['completion_lag_days'] as List? ?? []).cast<int>(),
        avgCompletionDays: (json['avg_completion_days'] as num?)?.toDouble(),
      );
}
