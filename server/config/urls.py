import os

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

# Flutter SPA fallback — если FLUTTER_WEB_DIR задан,
# все неизвестные URL отдают index.html (SPA routing)
_flutter_dir = os.environ.get('FLUTTER_WEB_DIR', '')
if _flutter_dir:
    def _spa_fallback(request, path=''):
        index = os.path.join(_flutter_dir, 'index.html')
        if os.path.isfile(index):
            return FileResponse(open(index, 'rb'), content_type='text/html')
        return HttpResponseNotFound('index.html not found')

    urlpatterns += [
        re_path(r'^(?!api/|admin/|media/|static/)(?P<path>.*)$', _spa_fallback),
    ]
