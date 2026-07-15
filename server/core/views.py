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


def serve_release(request, path):
    """Публичная раздача APK-релизов — БЕЗ авторизации (Kaiten #67040240).

    Файлы лежат в MEDIA_ROOT/releases/. Локально их обычно отдаёт nginx
    напрямую; на стендах (Coolify, без nginx) — этот view через Django.
    """
    base = (Path(settings.MEDIA_ROOT) / 'releases').resolve()
    file_path = (base / path).resolve()
    if not file_path.is_file() or not file_path.is_relative_to(base):
        return HttpResponseNotFound('Файл не найден.')

    content_type, _ = mimetypes.guess_type(str(file_path))
    return FileResponse(
        open(file_path, 'rb'),
        content_type=content_type or 'application/vnd.android.package-archive',
    )


def serve_docs(request, path=''):
    """Публичная раздача документации (руководство врача) — БЕЗ авторизации.

    Включается переменной окружения DOCS_DIR (путь к папке docs). Если она не
    задана, маршрут /docs/ не регистрируется вовсе (см. config/urls.py).
    Локально /docs/ проксирует на Django nginx; на стендах (Coolify, без nginx)
    файлы отдаёт этот view напрямую. Каталог отдаётся как index.html.
    """
    base = Path(settings.DOCS_DIR).resolve()
    target = (base / path).resolve()
    if not target.is_relative_to(base):
        return HttpResponseNotFound('Файл не найден.')
    if target.is_dir():
        target = target / 'index.html'
    if not target.is_file():
        return HttpResponseNotFound('Файл не найден.')

    content_type, _ = mimetypes.guess_type(str(target))
    return FileResponse(
        open(target, 'rb'),
        content_type=content_type or 'application/octet-stream',
    )
