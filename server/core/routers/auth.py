from django.contrib.auth import authenticate
from django.shortcuts import get_object_or_404
from ninja import Router, Schema

from ..auth import create_doctor_tokens, refresh_doctor_access_token
from ..models import DeviceToken, Doctor, Patient

router = Router()


class ErrorSchema(Schema):
    detail: str


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
    user = authenticate(username=payload.username, password=payload.password)
    if user is None:
        return 401, {'detail': 'Неверные учётные данные.'}

    patient = get_object_or_404(Patient, user=user)

    device_token = DeviceToken.objects.create(
        patient=patient,
        device_info=payload.device_info,
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


@router.post('/doctor/login', response={200: DoctorTokenResponse, 401: ErrorSchema, 403: ErrorSchema})
def doctor_login(request, payload: DoctorLoginRequest):
    """Авторизация врача по логину + пароль, возвращает JWT access + refresh."""
    user = authenticate(username=payload.username, password=payload.password)
    if user is None:
        return 401, {'detail': 'Неверные учётные данные.'}

    try:
        doctor = user.doctor_profile
    except Doctor.DoesNotExist:
        return 403, {'detail': 'Пользователь не является врачом.'}

    tokens = create_doctor_tokens(doctor)
    return 200, tokens


@router.post('/doctor/refresh', response={200: DoctorAccessResponse, 401: ErrorSchema})
def doctor_refresh(request, payload: DoctorRefreshRequest):
    """Обновление access токена по refresh."""
    access = refresh_doctor_access_token(payload.refresh)
    if access is None:
        return 401, {'detail': 'Невалидный refresh токен.'}
    return 200, {'access': access}
