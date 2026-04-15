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
_flutter_dir = os.environ.get('FLUTTER_WEB_DIR', '')
if _flutter_dir:
    def _doctor_spa_fallback(request, path=''):
        """Doctor app — /doctors/*"""
        doctor_dir = os.path.join(_flutter_dir, 'doctor')
        # Пробуем отдать статический файл (js, css, assets)
        file_path = os.path.join(doctor_dir, path)
        if path and os.path.isfile(file_path):
            return FileResponse(open(file_path, 'rb'))
        # Иначе — SPA fallback на index.html
        index = os.path.join(doctor_dir, 'index.html')
        if os.path.isfile(index):
            return FileResponse(open(index, 'rb'), content_type='text/html')
        return HttpResponseNotFound('doctor app not found')

    def _patient_spa_fallback(request, path=''):
        """Patient app — /*"""
        patient_dir = os.path.join(_flutter_dir, 'patient')
        # Пробуем отдать статический файл
        file_path = os.path.join(patient_dir, path)
        if path and os.path.isfile(file_path):
            return FileResponse(open(file_path, 'rb'))
        # Иначе — SPA fallback
        index = os.path.join(patient_dir, 'index.html')
        if os.path.isfile(index):
            return FileResponse(open(index, 'rb'), content_type='text/html')
        return HttpResponseNotFound('patient app not found')

    urlpatterns += [
        re_path(r'^doctors/(?P<path>.*)$', _doctor_spa_fallback),
        re_path(r'^(?!api/|admin/|media/|static/|doctors/)(?P<path>.*)$', _patient_spa_fallback),
    ]
