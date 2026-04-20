"""Тесты: все защищённые EP возвращают 401 без авторизации и с чужим типом токена."""
from django.test import TestCase

from .helpers import APITestBase


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

    def test_doctor_create_patient_requires_auth(self):
        resp = self.client.post(
            '/api/doctors/patients',
            data='{"username": "x", "password": "y"}',
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_doctor_set_starting_sound_requires_auth(self):
        resp = self.client.put(
            '/api/doctors/patients/1/starting-sound',
            data='{"audio_file_id": 1}',
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_doctor_update_patient_requires_auth(self):
        resp = self.client.patch(
            '/api/doctors/patients/1',
            data='{"birth_date": "1990-01-01"}',
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_doctor_quizzes_requires_auth(self):
        resp = self.client.get('/api/doctors/quizzes')
        self.assertEqual(resp.status_code, 401)

    def test_doctor_assign_quiz_requires_auth(self):
        resp = self.client.post(
            '/api/doctors/patients/1/assign-quiz',
            data='{"quiz_id": 1}',
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_doctor_assignments_requires_auth(self):
        resp = self.client.get('/api/doctors/patients/1/assignments')
        self.assertEqual(resp.status_code, 401)

    def test_doctor_unassign_quiz_requires_auth(self):
        resp = self.client.delete('/api/doctors/patients/1/assignments/1')
        self.assertEqual(resp.status_code, 401)

    def test_doctor_quiz_audio_requires_auth(self):
        resp = self.client.get('/api/doctors/quizzes/1/audio')
        self.assertEqual(resp.status_code, 401)

    def test_doctor_audio_library_requires_auth(self):
        resp = self.client.get('/api/doctors/audio-library')
        self.assertEqual(resp.status_code, 401)

    def test_doctor_categories_requires_auth(self):
        resp = self.client.get('/api/doctors/audio-library/categories')
        self.assertEqual(resp.status_code, 401)

    def test_doctor_notifications_requires_auth(self):
        resp = self.client.get('/api/doctors/notifications')
        self.assertEqual(resp.status_code, 401)

    def test_doctor_list_requires_auth(self):
        resp = self.client.get('/api/doctors/list')
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


class CrossAuthTest(APITestBase):
    """Кросс-тесты: пациент не может вызвать doctor API, врач — patient API."""

    # --- Пациент с device token → doctor endpoints → 401 ---

    def test_patient_token_rejected_by_doctor_me(self):
        resp = self.client.get('/api/doctors/me', **self.patient_headers())
        self.assertEqual(resp.status_code, 401)

    def test_patient_token_rejected_by_doctor_patients(self):
        resp = self.client.get('/api/doctors/me/patients', **self.patient_headers())
        self.assertEqual(resp.status_code, 401)

    def test_patient_token_rejected_by_doctor_quizzes(self):
        resp = self.client.get('/api/doctors/quizzes', **self.patient_headers())
        self.assertEqual(resp.status_code, 401)

    def test_patient_token_rejected_by_doctor_audio_library(self):
        resp = self.client.get('/api/doctors/audio-library', **self.patient_headers())
        self.assertEqual(resp.status_code, 401)

    def test_patient_token_rejected_by_doctor_categories(self):
        resp = self.client.get('/api/doctors/audio-library/categories', **self.patient_headers())
        self.assertEqual(resp.status_code, 401)

    def test_patient_token_rejected_by_doctor_notifications(self):
        resp = self.client.get('/api/doctors/notifications', **self.patient_headers())
        self.assertEqual(resp.status_code, 401)

    def test_patient_token_rejected_by_doctor_list(self):
        resp = self.client.get('/api/doctors/list', **self.patient_headers())
        self.assertEqual(resp.status_code, 401)

    def test_patient_token_rejected_by_doctor_transfer(self):
        resp = self.client.post(
            '/api/doctors/transfer-patient',
            data='{"patient_id": 1, "to_doctor_id": "00000000-0000-0000-0000-000000000000"}',
            content_type='application/json',
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 401)

    def test_patient_token_rejected_by_doctor_create_patient(self):
        resp = self.client.post(
            '/api/doctors/patients',
            data='{"username": "x", "password": "y"}',
            content_type='application/json',
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 401)

    # --- Врач с JWT → patient endpoints → 401 ---

    def test_doctor_jwt_rejected_by_patients_me(self):
        resp = self.client.get('/api/patients/me', **self.doctor_headers())
        self.assertEqual(resp.status_code, 401)

    def test_doctor_jwt_rejected_by_patients_quizzes(self):
        resp = self.client.get('/api/patients/me/quizzes', **self.doctor_headers())
        self.assertEqual(resp.status_code, 401)

    def test_doctor_jwt_rejected_by_patients_results(self):
        resp = self.client.get('/api/patients/me/results', **self.doctor_headers())
        self.assertEqual(resp.status_code, 401)

    def test_doctor_jwt_rejected_by_quiz_detail(self):
        resp = self.client.get(f'/api/quizzes/{self.quiz.id}', **self.doctor_headers())
        self.assertEqual(resp.status_code, 401)

    def test_doctor_jwt_rejected_by_quiz_audio(self):
        resp = self.client.get(f'/api/quizzes/{self.quiz.id}/audio', **self.doctor_headers())
        self.assertEqual(resp.status_code, 401)

    def test_doctor_jwt_rejected_by_quiz_submit(self):
        resp = self.client.post(
            f'/api/quizzes/{self.quiz.id}/submit',
            data='{"answers": []}',
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 401)
