import os

from django.conf import settings
from django.contrib import admin
from django.http import FileResponse, HttpResponseNotFound
from django.urls import path, re_path

from core.api import api
from core.views import serve_protected_media

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/', api.urls),
    re_path(r'^media/(?P<path>.*)$', serve_protected_media),
]

if 'debug_toolbar' in settings.INSTALLED_APPS:
    from debug_toolbar.toolbar import debug_toolbar_urls
    urlpatterns += debug_toolbar_urls()

# Flutter SPA fallback — если FLUTTER_WEB_DIR задан,
# Django раздаёт patient app (/) и doctor app (/doctors/).
#
# Структура FLUTTER_WEB_DIR:
#   flutter_web/patient/index.html  — patient app
#   flutter_web/doctor/index.html   — doctor app
_flutter_dir = os.environ.get('FLUTTER_WEB_DIR', '')
if _flutter_dir:
    import mimetypes

    def _serve_flutter_file(base_dir, path):
        """Отдать статический файл Flutter-приложения с правильным content-type."""
        file_path = os.path.join(base_dir, path)
        if path and os.path.isfile(file_path):
            content_type, _ = mimetypes.guess_type(file_path)
            return FileResponse(open(file_path, 'rb'), content_type=content_type)
        return None

    def _serve_flutter_index(base_dir):
        """Отдать index.html Flutter-приложения (SPA fallback)."""
        index = os.path.join(base_dir, 'index.html')
        if os.path.isfile(index):
            return FileResponse(open(index, 'rb'), content_type='text/html')
        return None

    _doctor_dir = os.path.join(_flutter_dir, 'doctor')
    _patient_dir = os.path.join(_flutter_dir, 'patient')

    def _doctor_spa_fallback(request, path=''):
        """Doctor app — /doctors/*"""
        resp = _serve_flutter_file(_doctor_dir, path)
        if resp:
            return resp
        resp = _serve_flutter_index(_doctor_dir)
        if resp:
            return resp
        return HttpResponseNotFound('doctor app not found')

    def _patient_spa_fallback(request, path=''):
        """Patient app — /*"""
        resp = _serve_flutter_file(_patient_dir, path)
        if resp:
            return resp
        resp = _serve_flutter_index(_patient_dir)
        if resp:
            return resp
        return HttpResponseNotFound('patient app not found')

    urlpatterns += [
        re_path(r'^doctors/(?P<path>.*)$', _doctor_spa_fallback),
        re_path(r'^(?!api/|admin/|media/|static/|doctors/)(?P<path>.*)$', _patient_spa_fallback),
    ]
