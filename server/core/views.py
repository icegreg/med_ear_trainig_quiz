import mimetypes
from pathlib import Path

from django.conf import settings
from django.http import FileResponse, HttpResponseForbidden, HttpResponseNotFound

from .models import DeviceToken, Doctor


def serve_protected_media(request, path):
    """Раздача медиа-файлов с проверкой аутентификации (device token или JWT).

    Токен может передаваться в заголовке `Authorization: Bearer <token>` либо
    в query-параметре `?token=<token>` (нужно для HTML5 audio/video на web,
    где кастомные заголовки не отправляются).
    """
    auth_header = request.headers.get('Authorization', '')
    if auth_header.startswith('Bearer '):
        token = auth_header[7:]
    else:
        token = request.GET.get('token', '')
    if not token:
        return HttpResponseForbidden('Требуется авторизация.')

    authenticated = False

    # Проверка device token (пациент)
    if DeviceToken.objects.filter(token=token, is_active=True).exists():
        authenticated = True

    # Проверка JWT (врач)
    if not authenticated:
        import jwt
        try:
            payload = jwt.decode(token, settings.SECRET_KEY, algorithms=['HS256'])
            if payload.get('type') == 'access':
                if Doctor.objects.filter(id=payload['doctor_id']).exists():
                    authenticated = True
        except jwt.InvalidTokenError:
            pass

    if not authenticated:
        return HttpResponseForbidden('Неверный токен.')

    file_path = Path(settings.MEDIA_ROOT) / path
    if not file_path.is_file() or not file_path.resolve().is_relative_to(
        Path(settings.MEDIA_ROOT).resolve()
    ):
        return HttpResponseNotFound('Файл не найден.')

    content_type, _ = mimetypes.guess_type(str(file_path))
    return FileResponse(open(file_path, 'rb'), content_type=content_type)
