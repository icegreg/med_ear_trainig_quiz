"""Тесты API врачей."""
import json

from core.models import AudioFile, Patient, PatientQuizAssignment, Quiz, QuizQuestion
from django.contrib.auth.models import User
from django.core.files.uploadedfile import SimpleUploadedFile

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


class CreatePatientTest(APITestBase):

    def test_create_patient(self):
        resp = self.client.post(
            '/api/doctors/patients',
            data=json.dumps({'username': 'new_patient', 'password': 'pass123'}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data['username'], 'new_patient')
        patient = Patient.objects.get(id=data['id'])
        self.assertEqual(patient.doctor, self.doctor)

    def test_create_patient_duplicate_username(self):
        resp = self.client.post(
            '/api/doctors/patients',
            data=json.dumps({'username': 'patient1', 'password': 'pass123'}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 400)


class StartingSoundTest(APITestBase):

    def test_set_starting_sound(self):
        resp = self.client.put(
            f'/api/doctors/patients/{self.patient.id}/starting-sound',
            data=json.dumps({'audio_file_id': self.audio.id}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.patient.refresh_from_db()
        self.assertEqual(self.patient.starting_sound, self.audio)

    def test_clear_starting_sound(self):
        self.patient.starting_sound = self.audio
        self.patient.save()
        resp = self.client.put(
            f'/api/doctors/patients/{self.patient.id}/starting-sound',
            data=json.dumps({'audio_file_id': None}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.patient.refresh_from_db()
        self.assertIsNone(self.patient.starting_sound)

    def test_set_starting_sound_not_found(self):
        resp = self.client.put(
            f'/api/doctors/patients/{self.patient.id}/starting-sound',
            data=json.dumps({'audio_file_id': 99999}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 404)

    def test_patient_profile_includes_starting_sound(self):
        self.patient.starting_sound = self.audio
        self.patient.save()
        resp = self.client.get('/api/patients/me', **self.patient_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data['starting_sound_id'], self.audio.id)
        self.assertIsNotNone(data['starting_sound_url'])


class DoctorQuizzesTest(APITestBase):

    def test_list_quizzes(self):
        resp = self.client.get('/api/doctors/quizzes', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertGreaterEqual(len(data), 1)
        self.assertEqual(data[0]['title'], 'Тест слуха')
        self.assertEqual(data[0]['question_count'], 1)

    def test_list_doctors(self):
        resp = self.client.get('/api/doctors/list', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        ids = [d['id'] for d in data]
        self.assertNotIn(str(self.doctor.id), ids)
        self.assertIn(str(self.doctor2.id), ids)


class AssignQuizTest(APITestBase):

    def test_assign_quiz(self):
        # Создаём новый квиз для назначения (base assignment уже существует)
        quiz2 = Quiz.objects.create(title='Квиз 2')
        QuizQuestion.objects.create(
            quiz=quiz2, text='Вопрос', options=['да', 'нет'],
            correct_answer='да', order=1,
        )
        resp = self.client.post(
            f'/api/doctors/patients/{self.patient.id}/assign-quiz',
            data=json.dumps({'quiz_id': quiz2.id}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data['quiz_title'], 'Квиз 2')
        self.assertEqual(data['status'], 'assigned')

    def test_assign_duplicate_rejected(self):
        resp = self.client.post(
            f'/api/doctors/patients/{self.patient.id}/assign-quiz',
            data=json.dumps({'quiz_id': self.quiz.id}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 400)

    def test_get_patient_assignments(self):
        resp = self.client.get(
            f'/api/doctors/patients/{self.patient.id}/assignments',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertGreaterEqual(len(data), 1)
