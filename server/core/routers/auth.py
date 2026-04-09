import logging

from django.conf import settings
from django.contrib.auth import authenticate
from django.http import JsonResponse
from django.shortcuts import get_object_or_404
from ninja import Router, Schema
from django_ratelimit.core import is_ratelimited

from ..auth import create_doctor_tokens, refresh_doctor_access_token
from ..models import DeviceToken, Doctor, Patient

router = Router()
logger = logging.getLogger('core.auth')


class ErrorSchema(Schema):
    detail: str


def _get_client_ip(request):
    xff = request.META.get('HTTP_X_FORWARDED_FOR')
    if xff:
        return xff.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR', 'unknown')


def _check_rate_limit(request, group):
    """Проверяет rate limit. Возвращает JsonResponse(429) или None."""
    rate = getattr(settings, 'AUTH_RATE_LIMIT', '5/m')
    if is_ratelimited(
        request, group=group, key='ip', rate=rate, increment=True
    ):
        ip = _get_client_ip(request)
        logger.warning('Rate limit exceeded for %s from IP %s', group, ip)
        return JsonResponse(
            {'detail': 'Слишком много попыток. Попробуйте позже.'},
            status=429,
        )
    return None


# --- Device Token (пациент) ---

class DeviceTokenRequest(Schema):
    username: str
    password: str
    device_info: str = ''


class DeviceTokenResponse(Schema):
    token: str
    patient_id: int


@router.post('/device-token', response={200: DeviceTokenResponse, 401: ErrorSchema})
def obtain_device_token(request, payload: DeviceTokenRequest):
    """Пациент авторизуется логином/паролем, получает долгоживущий device token."""
    limited = _check_rate_limit(request, 'auth-device-token')
    if limited:
        return limited

    ip = _get_client_ip(request)
    user = authenticate(username=payload.username, password=payload.password)

    if user is None:
        logger.warning(
            'Failed patient login: username=%s ip=%s',
            payload.username, ip,
        )
        return 401, {'detail': 'Неверные учётные данные.'}

    try:
        patient = Patient.objects.get(user=user)
    except Patient.DoesNotExist:
        logger.warning(
            'Login by non-patient user: username=%s ip=%s',
            payload.username, ip,
        )
        return 401, {'detail': 'Неверные учётные данные.'}

    device_token = DeviceToken.objects.create(
        patient=patient,
        device_info=payload.device_info,
    )

    logger.info(
        'Patient login: username=%s patient_id=%s ip=%s',
        payload.username, patient.id, ip,
    )
    return 200, {'token': device_token.token, 'patient_id': patient.id}


# --- JWT (врач) ---

class DoctorLoginRequest(Schema):
    username: str
    password: str


class DoctorTokenResponse(Schema):
    access: str
    refresh: str


class DoctorRefreshRequest(Schema):
    refresh: str


class DoctorAccessResponse(Schema):
    access: str


@router.post('/doctor/login', response={200: DoctorTokenResponse, 401: ErrorSchema})
def doctor_login(request, payload: DoctorLoginRequest):
    """Авторизация врача по логину + пароль, возвращает JWT access + refresh."""
    limited = _check_rate_limit(request, 'auth-doctor-login')
    if limited:
        return limited

    ip = _get_client_ip(request)
    user = authenticate(username=payload.username, password=payload.password)

    if user is None:
        logger.warning(
            'Failed doctor login: username=%s ip=%s',
            payload.username, ip,
        )
        return 401, {'detail': 'Неверные учётные данные.'}

    try:
        doctor = user.doctor_profile
    except Doctor.DoesNotExist:
        # Единый ответ — не раскрываем что пользователь не врач
        logger.warning(
            'Login by non-doctor user: username=%s ip=%s',
            payload.username, ip,
        )
        return 401, {'detail': 'Неверные учётные данные.'}

    logger.info(
        'Doctor login: username=%s doctor_id=%s ip=%s',
        payload.username, doctor.id, ip,
    )
    tokens = create_doctor_tokens(doctor)
    return 200, tokens


@router.post('/doctor/refresh', response={200: DoctorAccessResponse, 401: ErrorSchema})
def doctor_refresh(request, payload: DoctorRefreshRequest):
    """Обновление access токена по refresh."""
    access = refresh_doctor_access_token(payload.refresh)
    if access is None:
        return 401, {'detail': 'Невалидный refresh токен.'}
    return 200, {'access': access}
