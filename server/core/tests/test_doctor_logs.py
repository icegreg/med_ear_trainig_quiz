"""Тесты журнала действий врача и пометки о смене пароля в логе пациента."""
import json
import shutil
import tempfile

from django.test import override_settings
from django.utils import timezone

from core import client_logs, doctor_logs
from core.models import PatientQuizAssignment, Quiz

from .helpers import APITestBase


class DoctorLogTestBase(APITestBase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self._override = override_settings(CLIENT_LOGS_DIR=self.tmp)
        self._override.enable()

    def tearDown(self):
        self._override.disable()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _doctor_entries(self):
        return [json.loads(ln) for ln in doctor_logs.read_tail(self.doctor.id)]

    def _patient_entries(self):
        return [json.loads(ln) for ln in client_logs.read_tail(self.patient.id)]


class AssignUnassignLogTest(DoctorLogTestBase):

    def test_assign_is_logged(self):
        quiz = Quiz.objects.create(title='Новый тест')
        resp = self.client.post(
            f'/api/doctors/patients/{self.patient.id}/assign-quiz',
            data=json.dumps({'quiz_id': quiz.id}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        entries = self._doctor_entries()
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]['action'], 'assign_quiz')
        self.assertEqual(entries[0]['detail'], 'Новый тест')
        self.assertEqual(entries[0]['patient_id'], self.patient.id)

    def test_unassign_is_logged(self):
        # Базовое назначение cls.assignment (assigned) снимаем через API.
        resp = self.client.delete(
            f'/api/doctors/patients/{self.patient.id}/assignments/{self.assignment.id}',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        entries = self._doctor_entries()
        self.assertEqual(entries[-1]['action'], 'unassign_quiz')
        self.assertEqual(entries[-1]['detail'], self.quiz.title)


class ReviewLogTest(DoctorLogTestBase):

    def test_review_logged_when_something_marked(self):
        q = Quiz.objects.create(title='T')
        PatientQuizAssignment.objects.create(
            patient=self.patient, quiz=q,
            status=PatientQuizAssignment.Status.COMPLETED,
        )
        resp = self.client.post(
            f'/api/doctors/patients/{self.patient.id}/mark-results-viewed',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        entries = self._doctor_entries()
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]['action'], 'review_results')

    def test_review_not_logged_when_nothing_to_mark(self):
        # Нет непросмотренных пройденных тестов → записи в лог нет.
        resp = self.client.post(
            f'/api/doctors/patients/{self.patient.id}/mark-results-viewed',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self._doctor_entries(), [])


class ResetPasswordLogTest(DoctorLogTestBase):
    SECRET = 'SuperSecret123'

    def _reset(self):
        return self.client.post(
            f'/api/doctors/patients/{self.patient.id}/reset-password',
            data=json.dumps({'new_password': self.SECRET}),
            content_type='application/json',
            **self.doctor_headers(),
        )

    def test_reset_logged_without_password(self):
        resp = self._reset()
        self.assertEqual(resp.status_code, 200)
        entries = self._doctor_entries()
        self.assertEqual(entries[-1]['action'], 'reset_password')
        # Пароль не должен фигурировать в файле лога врача.
        raw = doctor_logs.log_path(self.doctor.id).read_text(encoding='utf-8')
        self.assertNotIn(self.SECRET, raw)

    def test_patient_log_gets_marker_without_password(self):
        self._reset()
        entries = self._patient_entries()
        self.assertTrue(any(e.get('event') == 'password_changed' for e in entries))
        raw = client_logs.log_path(self.patient.id).read_text(encoding='utf-8')
        self.assertNotIn(self.SECRET, raw)
