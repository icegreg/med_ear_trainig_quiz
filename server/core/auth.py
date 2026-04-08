from datetime import datetime, timedelta, timezone

import jwt
from django.conf import settings
from django.utils import timezone as dj_timezone
from ninja.security import HttpBearer

from .models import DeviceToken, Doctor


class DeviceTokenAuth(HttpBearer):
    """Аутентификация пациента по device token (Header: Authorization: Bearer <token>)."""

    def authenticate(self, request, token: str):
        try:
            device_token = DeviceToken.objects.select_related(
                'patient__user'
            ).get(token=token, is_active=True)
        except DeviceToken.DoesNotExist:
            return None

        device_token.last_used_at = dj_timezone.now()
        device_token.save(update_fields=['last_used_at'])

        request.patient = device_token.patient
        request.user = device_token.patient.user
        return device_token


class DoctorJWTAuth(HttpBearer):
    """Аутентификация врача по JWT (Header: Authorization: Bearer <jwt>)."""

    def authenticate(self, request, token: str):
        try:
            payload = jwt.decode(
                token, settings.SECRET_KEY, algorithms=['HS256']
            )
        except jwt.ExpiredSignatureError:
            return None
        except jwt.InvalidTokenError:
            return None

        if payload.get('type') != 'access':
            return None

        try:
            doctor = Doctor.objects.get(id=payload['doctor_id'])
        except Doctor.DoesNotExist:
            return None

        request.doctor = doctor
        return doctor


def create_doctor_tokens(doctor: Doctor) -> dict:
    """Генерация access + refresh JWT токенов для врача."""
    now = datetime.now(timezone.utc)

    access_payload = {
        'doctor_id': str(doctor.id),
        'type': 'access',
        'exp': now + timedelta(hours=24),
        'iat': now,
    }
    refresh_payload = {
        'doctor_id': str(doctor.id),
        'type': 'refresh',
        'exp': now + timedelta(days=30),
        'iat': now,
    }

    return {
        'access': jwt.encode(access_payload, settings.SECRET_KEY, algorithm='HS256'),
        'refresh': jwt.encode(refresh_payload, settings.SECRET_KEY, algorithm='HS256'),
    }


def refresh_doctor_access_token(refresh_token: str) -> str | None:
    """Обновление access токена по refresh токену."""
    try:
        payload = jwt.decode(
            refresh_token, settings.SECRET_KEY, algorithms=['HS256']
        )
    except jwt.InvalidTokenError:
        return None

    if payload.get('type') != 'refresh':
        return None

    try:
        doctor = Doctor.objects.get(id=payload['doctor_id'])
    except Doctor.DoesNotExist:
        return None

    now = datetime.now(timezone.utc)
    access_payload = {
        'doctor_id': str(doctor.id),
        'type': 'access',
        'exp': now + timedelta(hours=24),
        'iat': now,
    }
    return jwt.encode(access_payload, settings.SECRET_KEY, algorithm='HS256')
