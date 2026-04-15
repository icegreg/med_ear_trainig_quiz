class AppNotification {
  final int id;
  final String type;
  final String message;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'],
        type: json['type'],
        message: json['message'],
        data: Map<String, dynamic>.from(json['data'] ?? {}),
        isRead: json['is_read'],
        createdAt: DateTime.parse(json['created_at']),
      );
}
