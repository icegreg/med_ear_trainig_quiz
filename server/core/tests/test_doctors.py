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


class UpdatePatientTest(APITestBase):

    def test_set_birth_date(self):
        resp = self.client.patch(
            f'/api/doctors/patients/{self.patient.id}',
            data=json.dumps({'birth_date': '1990-05-17'}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()['birth_date'], '1990-05-17')
        self.patient.refresh_from_db()
        self.assertEqual(str(self.patient.birth_date), '1990-05-17')

    def test_set_fio(self):
        resp = self.client.patch(
            f'/api/doctors/patients/{self.patient.id}',
            data=json.dumps({
                'last_name': 'Иванов',
                'first_name': 'Пётр',
                'patronymic': 'Сергеевич',
            }),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data['last_name'], 'Иванов')
        self.assertEqual(data['first_name'], 'Пётр')
        self.assertEqual(data['patronymic'], 'Сергеевич')
        self.assertEqual(data['full_name'], 'Иванов Пётр Сергеевич')

    def test_clear_birth_date(self):
        from datetime import date
        self.patient.birth_date = date(1990, 5, 17)
        self.patient.save()
        resp = self.client.patch(
            f'/api/doctors/patients/{self.patient.id}',
            data=json.dumps({'birth_date': None}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.patient.refresh_from_db()
        self.assertIsNone(self.patient.birth_date)

    def test_update_patient_of_another_doctor_404(self):
        other_user = User.objects.create_user(username='other_patient', password='x')
        other = Patient.objects.create(user=other_user, doctor=None)
        resp = self.client.patch(
            f'/api/doctors/patients/{other.id}',
            data=json.dumps({'birth_date': '2000-01-01'}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 404)

    def test_patients_list_includes_birth_date(self):
        from datetime import date
        self.patient.birth_date = date(1985, 3, 10)
        self.patient.save()
        resp = self.client.get('/api/doctors/me/patients', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()[0]['birth_date'], '1985-03-10')


class PatientsListSearchSortTest(APITestBase):

    def _make_patient(self, username, last, first):
        u = User.objects.create_user(username=username, password='x')
        return Patient.objects.create(
            user=u, doctor=self.doctor,
            last_name=last, first_name=first,
        )

    def test_sorted_by_last_name(self):
        self._make_patient('p_smith', 'Смирнов', 'Алексей')
        self._make_patient('p_ivanov', 'Иванов', 'Борис')
        # self.patient (patient1) has empty last_name — идёт первым
        resp = self.client.get('/api/doctors/me/patients', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        last_names = [p['last_name'] for p in resp.json()]
        self.assertEqual(last_names, ['', 'Иванов', 'Смирнов'])

    def test_search_by_last_name(self):
        self._make_patient('p_smith', 'Смирнов', 'Алексей')
        self._make_patient('p_ivanov', 'Иванов', 'Борис')
        resp = self.client.get(
            '/api/doctors/me/patients?search=смир',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['last_name'], 'Смирнов')

    def test_search_by_first_name(self):
        self._make_patient('p_smith', 'Смирнов', 'Алексей')
        self._make_patient('p_ivanov', 'Иванов', 'Борис')
        resp = self.client.get(
            '/api/doctors/me/patients?search=борис',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['first_name'], 'Борис')

    def test_list_includes_assigned_and_completed_counts(self):
        # self.patient уже имеет одно assigned назначение (self.assignment)
        # Добавим ещё одно completed
        extra_quiz = Quiz.objects.create(title='Extra')
        PatientQuizAssignment.objects.create(
            patient=self.patient, quiz=extra_quiz,
            status=PatientQuizAssignment.Status.COMPLETED,
        )
        resp = self.client.get('/api/doctors/me/patients', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        patient = next(p for p in data if p['id'] == self.patient.id)
        self.assertEqual(patient['assigned_count'], 1)
        self.assertEqual(patient['completed_count'], 1)

    def test_create_patient_with_fio(self):
        resp = self.client.post(
            '/api/doctors/patients',
            data=json.dumps({
                'username': 'fio_pat',
                'password': 'pass123',
                'last_name': 'Кузнецов',
                'first_name': 'Игорь',
                'patronymic': 'Олегович',
                'birth_date': '1975-02-28',
            }),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        created = Patient.objects.get(user__username='fio_pat')
        self.assertEqual(created.last_name, 'Кузнецов')
        self.assertEqual(created.first_name, 'Игорь')
        self.assertEqual(created.patronymic, 'Олегович')
        self.assertEqual(str(created.birth_date), '1975-02-28')


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

    def test_unassign_quiz(self):
        resp = self.client.delete(
            f'/api/doctors/patients/{self.patient.id}/assignments/{self.assignment.id}',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(
            PatientQuizAssignment.objects.filter(id=self.assignment.id).exists()
        )

    def test_unassign_completed_rejected(self):
        self.assignment.status = PatientQuizAssignment.Status.COMPLETED
        self.assignment.save()
        resp = self.client.delete(
            f'/api/doctors/patients/{self.patient.id}/assignments/{self.assignment.id}',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 400)
        self.assertTrue(
            PatientQuizAssignment.objects.filter(id=self.assignment.id).exists()
        )

    def test_get_quiz_audio(self):
        resp = self.client.get(
            f'/api/doctors/quizzes/{self.quiz.id}/audio',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['id'], self.audio.id)

    def test_unassign_other_doctors_patient_404(self):
        other_user = User.objects.create_user(username='x_pat', password='x')
        other_patient = Patient.objects.create(user=other_user, doctor=self.doctor2)
        assignment = PatientQuizAssignment.objects.create(
            patient=other_patient, quiz=self.quiz,
        )
        resp = self.client.delete(
            f'/api/doctors/patients/{other_patient.id}/assignments/{assignment.id}',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 404)
