"""Тесты эндпоинтов авторизации."""
import json

from .helpers import APITestBase


class DeviceTokenAuthTest(APITestBase):

    def test_obtain_device_token_success(self):
        resp = self.client.post(
            '/api/auth/device-token',
            data=json.dumps({
                'username': 'patient1',
                'password': 'patpass123',
                'device_info': 'Test Device',
            }),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIn('token', data)
        self.assertEqual(data['patient_id'], self.patient.id)
        self.assertIn('expires_at', data)

    def test_obtain_device_token_expires_in_3_months(self):
        from datetime import timedelta

        from django.utils import timezone

        from core.models import DeviceToken

        resp = self.client.post(
            '/api/auth/device-token',
            data=json.dumps({'username': 'patient1', 'password': 'patpass123'}),
            content_type='application/json',
        )
        token = DeviceToken.objects.get(token=resp.json()['token'])
        delta = token.expires_at - timezone.now()
        self.assertGreater(delta, timedelta(days=89))
        self.assertLess(delta, timedelta(days=91))

    def test_expired_device_token_rejected(self):
        from datetime import timedelta

        from django.utils import timezone

        self.device_token.expires_at = timezone.now() - timedelta(seconds=1)
        self.device_token.save()
        resp = self.client.get('/api/patients/me', **self.patient_headers())
        self.assertEqual(resp.status_code, 401)
        # cleanup
        self.device_token.expires_at = timezone.now() + timedelta(days=90)
        self.device_token.save()

    def test_obtain_device_token_wrong_password(self):
        resp = self.client.post(
            '/api/auth/device-token',
            data=json.dumps({'username': 'patient1', 'password': 'wrong'}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_obtain_device_token_nonexistent_user(self):
        resp = self.client.post(
            '/api/auth/device-token',
            data=json.dumps({'username': 'nobody', 'password': 'x'}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_inactive_device_token_rejected(self):
        self.device_token.is_active = False
        self.device_token.save()
        resp = self.client.get('/api/patients/me', **self.patient_headers())
        self.assertEqual(resp.status_code, 401)
        # cleanup
        self.device_token.is_active = True
        self.device_token.save()


class DoctorJWTAuthTest(APITestBase):

    def test_doctor_login_success(self):
        resp = self.client.post(
            '/api/auth/doctor/login',
            data=json.dumps({'username': 'doctor1', 'password': 'docpass123'}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIn('access', data)
        self.assertIn('refresh', data)

    def test_doctor_login_wrong_password(self):
        resp = self.client.post(
            '/api/auth/doctor/login',
            data=json.dumps({'username': 'doctor1', 'password': 'wrong'}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_doctor_login_patient_user_denied(self):
        """Пациент не может авторизоваться как врач — единый 401 (без user enumeration)."""
        resp = self.client.post(
            '/api/auth/doctor/login',
            data=json.dumps({'username': 'patient1', 'password': 'patpass123'}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_doctor_refresh_success(self):
        # Сначала логинимся
        login_resp = self.client.post(
            '/api/auth/doctor/login',
            data=json.dumps({'username': 'doctor1', 'password': 'docpass123'}),
            content_type='application/json',
        )
        refresh_token = login_resp.json()['refresh']

        resp = self.client.post(
            '/api/auth/doctor/refresh',
            data=json.dumps({'refresh': refresh_token}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 200)
        self.assertIn('access', resp.json())

    def test_doctor_refresh_invalid_token(self):
        resp = self.client.post(
            '/api/auth/doctor/refresh',
            data=json.dumps({'refresh': 'invalid-token'}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_invalid_jwt_rejected(self):
        resp = self.client.get(
            '/api/doctors/me',
            HTTP_AUTHORIZATION='Bearer invalid-jwt-token',
        )
        self.assertEqual(resp.status_code, 401)
