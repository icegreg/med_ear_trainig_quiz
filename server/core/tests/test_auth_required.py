"""Тесты: все защищённые EP возвращают 401 без авторизации."""
from django.test import TestCase


class AuthRequiredTest(TestCase):
    """Проверяем что все EP кроме auth требуют авторизации."""

    # --- Patient endpoints (device token) ---

    def test_patients_me_requires_auth(self):
        resp = self.client.get('/api/patients/me')
        self.assertEqual(resp.status_code, 401)

    def test_patients_quizzes_requires_auth(self):
        resp = self.client.get('/api/patients/me/quizzes')
        self.assertEqual(resp.status_code, 401)

    def test_patients_results_requires_auth(self):
        resp = self.client.get('/api/patients/me/results')
        self.assertEqual(resp.status_code, 401)

    # --- Quiz endpoints (device token) ---

    def test_quiz_detail_requires_auth(self):
        resp = self.client.get('/api/quizzes/1')
        self.assertEqual(resp.status_code, 401)

    def test_quiz_audio_requires_auth(self):
        resp = self.client.get('/api/quizzes/1/audio')
        self.assertEqual(resp.status_code, 401)

    def test_quiz_submit_requires_auth(self):
        resp = self.client.post(
            '/api/quizzes/1/submit',
            data='{"answers": []}',
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    # --- Doctor endpoints (JWT) ---

    def test_doctor_me_requires_auth(self):
        resp = self.client.get('/api/doctors/me')
        self.assertEqual(resp.status_code, 401)

    def test_doctor_patients_requires_auth(self):
        resp = self.client.get('/api/doctors/me/patients')
        self.assertEqual(resp.status_code, 401)

    def test_doctor_patient_results_requires_auth(self):
        resp = self.client.get('/api/doctors/patients/1/results')
        self.assertEqual(resp.status_code, 401)

    def test_doctor_transfer_requires_auth(self):
        resp = self.client.post(
            '/api/doctors/transfer-patient',
            data='{"patient_id": 1, "to_doctor_id": "00000000-0000-0000-0000-000000000000"}',
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    # --- Media ---

    def test_media_requires_auth(self):
        resp = self.client.get('/media/audio/test.wav')
        self.assertEqual(resp.status_code, 403)

    # --- Auth endpoints — НЕ требуют авторизации ---

    def test_device_token_endpoint_no_auth_needed(self):
        resp = self.client.post(
            '/api/auth/device-token',
            data='{"username": "x", "password": "y"}',
            content_type='application/json',
        )
        # 401 от неверных данных, но не от отсутствия токена
        self.assertIn(resp.status_code, [401, 422])

    def test_doctor_login_no_auth_needed(self):
        resp = self.client.post(
            '/api/auth/doctor/login',
            data='{"username": "x", "password": "y"}',
            content_type='application/json',
        )
        self.assertIn(resp.status_code, [401, 422])

    def test_doctor_refresh_no_auth_needed(self):
        resp = self.client.post(
            '/api/auth/doctor/refresh',
            data='{"refresh": "invalid"}',
            content_type='application/json',
        )
        self.assertIn(resp.status_code, [401, 422])
