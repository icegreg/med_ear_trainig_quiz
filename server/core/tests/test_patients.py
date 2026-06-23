"""Тесты API пациентов."""
import json

from .helpers import APITestBase


class PatientProfileTest(APITestBase):

    def test_get_my_profile(self):
        resp = self.client.get('/api/patients/me', **self.patient_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data['id'], self.patient.id)
        self.assertEqual(data['username'], 'patient1')
        self.assertEqual(data['doctor_id'], str(self.doctor.id))


class PatientQuizzesTest(APITestBase):

    def test_get_my_quizzes(self):
        resp = self.client.get('/api/patients/me/quizzes', **self.patient_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['title'], 'Тест слуха')
        self.assertEqual(data[0]['status'], 'assigned')

    def test_get_my_quizzes_empty(self):
        """Пациент без назначений получает пустой список."""
        from django.contrib.auth.models import User
        from core.models import DeviceToken, Patient

        user2 = User.objects.create_user(username='patient2', password='pass')
        patient2 = Patient.objects.create(user=user2)
        token2 = DeviceToken.objects.create(patient=patient2)

        resp = self.client.get(
            '/api/patients/me/quizzes',
            HTTP_AUTHORIZATION=f'Bearer {token2.token}',
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json(), [])


class PatientResultsTest(APITestBase):

    def test_get_my_results_empty(self):
        resp = self.client.get('/api/patients/me/results', **self.patient_headers())
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json(), [])

    def test_get_my_results_after_submit(self):
        """После отправки ответов результат появляется в списке."""
        self.client.post(
            f'/api/quizzes/{self.quiz.id}/submit',
            data=json.dumps({
                'answers': [{'question_id': self.question.id, 'answer': 'B'}]
            }),
            content_type='application/json',
            **self.patient_headers(),
        )

        resp = self.client.get('/api/patients/me/results', **self.patient_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['quiz_title'], 'Тест слуха')
        self.assertEqual(data[0]['score'], 1)


class PatientChangePasswordTest(APITestBase):

    URL = '/api/patients/me/change-password'

    def _post(self, body, **extra):
        return self.client.post(
            self.URL,
            data=json.dumps(body),
            content_type='application/json',
            **extra,
        )

    def test_change_password_success(self):
        resp = self._post(
            {'old_password': 'patpass123', 'new_password': 'newStrongPass456'},
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()['status'], 'ok')

        self.patient_user.refresh_from_db()
        self.assertTrue(self.patient_user.check_password('newStrongPass456'))

    def test_change_password_wrong_old(self):
        resp = self._post(
            {'old_password': 'wrong', 'new_password': 'newStrongPass456'},
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 400)

        self.patient_user.refresh_from_db()
        self.assertTrue(self.patient_user.check_password('patpass123'))

    def test_change_password_same_as_old(self):
        resp = self._post(
            {'old_password': 'patpass123', 'new_password': 'patpass123'},
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 400)

    def test_change_password_too_weak(self):
        """Слишком короткий/простой пароль отклоняется валидаторами Django."""
        resp = self._post(
            {'old_password': 'patpass123', 'new_password': '123'},
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 400)

        self.patient_user.refresh_from_db()
        self.assertTrue(self.patient_user.check_password('patpass123'))

    def test_change_password_keeps_device_token_valid(self):
        """После смены пароля текущий device token продолжает работать."""
        self._post(
            {'old_password': 'patpass123', 'new_password': 'newStrongPass456'},
            **self.patient_headers(),
        )
        resp = self.client.get('/api/patients/me', **self.patient_headers())
        self.assertEqual(resp.status_code, 200)
