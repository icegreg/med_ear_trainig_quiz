"""Тесты API врачей."""
import json

from .helpers import APITestBase


class DoctorProfileTest(APITestBase):

    def test_get_doctor_profile(self):
        resp = self.client.get('/api/doctors/me', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data['last_name'], 'Петров')
        self.assertEqual(data['first_name'], 'Иван')
        self.assertEqual(data['patronymic'], 'Сергеевич')
        self.assertEqual(data['clinic'], 'Клиника №1')


class DoctorPatientsTest(APITestBase):

    def test_get_my_patients(self):
        resp = self.client.get('/api/doctors/me/patients', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['username'], 'patient1')

    def test_get_patient_results(self):
        # Сначала пациент сдаёт тест
        self.client.post(
            f'/api/quizzes/{self.quiz.id}/submit',
            data=json.dumps({
                'answers': [{'question_id': self.question.id, 'answer': 'B'}]
            }),
            content_type='application/json',
            **self.patient_headers(),
        )

        resp = self.client.get(
            f'/api/doctors/patients/{self.patient.id}/results',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['score'], 1)

    def test_cannot_see_other_doctors_patient(self):
        """Врач не может видеть результаты чужого пациента."""
        from core.auth import create_doctor_tokens
        tokens2 = create_doctor_tokens(self.doctor2)

        resp = self.client.get(
            f'/api/doctors/patients/{self.patient.id}/results',
            HTTP_AUTHORIZATION=f'Bearer {tokens2["access"]}',
        )
        self.assertEqual(resp.status_code, 404)


class TransferPatientTest(APITestBase):

    def test_transfer_patient_success(self):
        resp = self.client.post(
            '/api/doctors/transfer-patient',
            data=json.dumps({
                'patient_id': self.patient.id,
                'to_doctor_id': str(self.doctor2.id),
            }),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data['status'], 'ok')

        self.patient.refresh_from_db()
        self.assertEqual(self.patient.doctor_id, self.doctor2.id)

    def test_transfer_to_self_rejected(self):
        resp = self.client.post(
            '/api/doctors/transfer-patient',
            data=json.dumps({
                'patient_id': self.patient.id,
                'to_doctor_id': str(self.doctor.id),
            }),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 400)

    def test_transfer_other_doctors_patient_rejected(self):
        """Врач не может передать чужого пациента."""
        from core.auth import create_doctor_tokens
        tokens2 = create_doctor_tokens(self.doctor2)

        resp = self.client.post(
            '/api/doctors/transfer-patient',
            data=json.dumps({
                'patient_id': self.patient.id,
                'to_doctor_id': str(self.doctor.id),
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {tokens2["access"]}',
        )
        self.assertEqual(resp.status_code, 404)
