class AudioFile {
  final int id;
  final String title;
  final String fileUrl;
  final int? categoryId;
  final int? durationSeconds;
  final DateTime uploadedAt;

  AudioFile({
    required this.id,
    required this.title,
    required this.fileUrl,
    this.categoryId,
    this.durationSeconds,
    required this.uploadedAt,
  });

  factory AudioFile.fromJson(Map<String, dynamic> json) => AudioFile(
        id: json['id'],
        title: json['title'],
        fileUrl: json['file'],
        categoryId: json['category_id'],
        durationSeconds: json['duration_seconds'],
        uploadedAt: DateTime.parse(json['uploaded_at']),
      );
}
