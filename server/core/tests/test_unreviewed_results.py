"""Тесты статуса «непроверенные тесты» и отметки о просмотре."""
from django.contrib.auth.models import User
from django.utils import timezone

from core.models import Patient, PatientQuizAssignment, Quiz

from .helpers import APITestBase


class UnreviewedTestsBase(APITestBase):
    def _completed(self, patient=None, reviewed=False):
        patient = patient or self.patient
        quiz = Quiz.objects.create(title='Тест')
        return PatientQuizAssignment.objects.create(
            patient=patient,
            quiz=quiz,
            status=PatientQuizAssignment.Status.COMPLETED,
            reviewed_at=timezone.now() if reviewed else None,
        )

    def _me_in_list(self):
        resp = self.client.get('/api/doctors/me/patients', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        return next(p for p in resp.json() if p['id'] == self.patient.id)


class UnreviewedCountTest(UnreviewedTestsBase):

    def test_counts_completed_unreviewed(self):
        self._completed()
        self._completed()
        self._completed(reviewed=True)
        self.assertEqual(self._me_in_list()['unreviewed_count'], 2)

    def test_assigned_not_counted(self):
        # Базовое назначение (assigned) не считается непроверенным.
        self.assertEqual(self._me_in_list()['unreviewed_count'], 0)

    def test_zero_when_all_reviewed(self):
        self._completed(reviewed=True)
        self.assertEqual(self._me_in_list()['unreviewed_count'], 0)


class MarkResultsViewedTest(UnreviewedTestsBase):

    def test_marks_all_and_is_idempotent(self):
        a1 = self._completed()
        self._completed()
        resp = self.client.post(
            f'/api/doctors/patients/{self.patient.id}/mark-results-viewed',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()['reviewed'], 2)
        a1.refresh_from_db()
        self.assertIsNotNone(a1.reviewed_at)
        self.assertEqual(self._me_in_list()['unreviewed_count'], 0)

        # Повторный вызов ничего не меняет.
        resp2 = self.client.post(
            f'/api/doctors/patients/{self.patient.id}/mark-results-viewed',
            **self.doctor_headers(),
        )
        self.assertEqual(resp2.json()['reviewed'], 0)

    def test_requires_auth(self):
        resp = self.client.post(
            f'/api/doctors/patients/{self.patient.id}/mark-results-viewed',
        )
        self.assertEqual(resp.status_code, 401)

    def test_other_doctors_patient_404(self):
        other_user = User.objects.create_user(username='foreign2', password='x')
        foreign = Patient.objects.create(user=other_user, doctor=self.doctor2)
        self._completed(patient=foreign)
        resp = self.client.post(
            f'/api/doctors/patients/{foreign.id}/mark-results-viewed',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 404)
