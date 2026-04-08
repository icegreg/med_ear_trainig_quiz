class AudioFile {
  final int id;
  final String title;
  final String fileUrl;
  final int? durationSeconds;

  AudioFile({
    required this.id,
    required this.title,
    required this.fileUrl,
    this.durationSeconds,
  });

  factory AudioFile.fromJson(Map<String, dynamic> json) => AudioFile(
        id: json['id'],
        title: json['title'],
        fileUrl: json['file'],
        durationSeconds: json['duration_seconds'],
      );
}
