"""Публичный реестр релизов APK — без авторизации (Kaiten #67040240).

Реестр привязан к стенду (у preprod и prod свои БД), flavor константный.
Сами файлы отдаются по /releases/<file> (nginx локально, Django на стендах);
дефолтный релиз доступен по стабильной ссылке /releases/latest.apk.
"""
from ninja import Router

from ..models import Release
from ..schemas import ErrorSchema, ReleaseSchema

router = Router()


@router.get('/', response=list[ReleaseSchema])
def list_releases(request):
    """Все релизы стенда, свежие сверху."""
    return list(Release.objects.all())


@router.get('/latest', response={200: ReleaseSchema, 404: ErrorSchema})
def latest_release(request):
    """Дефолтный релиз (или самый свежий, если дефолт не задан)."""
    release = (
        Release.objects.filter(is_default=True).first()
        or Release.objects.order_by('-created_at').first()
    )
    if release is None:
        return 404, {'status': 'error', 'message': 'Нет доступных релизов.'}
    return release
