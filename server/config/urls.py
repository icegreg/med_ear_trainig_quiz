from django.contrib import admin
from django.urls import path, re_path

from core.api import api
from core.views import serve_protected_media

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/', api.urls),
    re_path(r'^media/(?P<path>.*)$', serve_protected_media),
]
