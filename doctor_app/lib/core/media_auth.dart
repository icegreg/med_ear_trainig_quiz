/// Добавляет access-токен в query-параметр URL медиа-файла.
/// HTML5 audio/video на web не поддерживает кастомные заголовки,
/// поэтому бэкенд принимает токен и через `?token=...` (см. serve_protected_media).
String withAuthToken(String url, String? token) {
  if (token == null || token.isEmpty) return url;
  final sep = url.contains('?') ? '&' : '?';
  return '$url${sep}token=${Uri.encodeQueryComponent(token)}';
}
