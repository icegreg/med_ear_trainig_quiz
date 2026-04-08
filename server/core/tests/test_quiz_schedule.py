"""Тесты временных рамок тестов (starts_at / ends_at)."""
import json
from datetime import timedelta

from django.utils import timezone

from .helpers import APITestBase


class QuizScheduleTest(APITestBase):

    def _set_schedule(self, starts_at=None, ends_at=None):
        self.assignment.starts_at = starts_at
        self.assignment.ends_at = ends_at
        self.assignment.save()

    def _submit(self):
        return self.client.post(
            f'/api/quizzes/{self.quiz.id}/submit',
            data=json.dumps({
                'answers': [{'question_id': self.question.id, 'answer': 'да'}]
            }),
            content_type='application/json',
            **self.patient_headers(),
        )

    # --- Null starts_at / ends_at — всегда доступен ---

    def test_null_schedule_is_available(self):
        self._set_schedule(starts_at=None, ends_at=None)
        resp = self._submit()
        self.assertEqual(resp.status_code, 200)

    # --- starts_at в будущем → тест недоступен ---

    def test_future_starts_at_blocks_submit(self):
        self._set_schedule(starts_at=timezone.now() + timedelta(days=1))
        resp = self._submit()
        self.assertEqual(resp.status_code, 403)
        self.assertIn('не доступен', resp.json()['message'])

    def test_future_starts_at_blocks_detail(self):
        self._set_schedule(starts_at=timezone.now() + timedelta(days=1))
        resp = self.client.get(
            f'/api/quizzes/{self.quiz.id}', **self.patient_headers()
        )
        self.assertEqual(resp.status_code, 403)

    def test_future_starts_at_blocks_audio(self):
        self._set_schedule(starts_at=timezone.now() + timedelta(days=1))
        resp = self.client.get(
            f'/api/quizzes/{self.quiz.id}/audio', **self.patient_headers()
        )
        self.assertEqual(resp.status_code, 403)

    # --- ends_at в прошлом → тест просрочен ---

    def test_expired_blocks_submit(self):
        self._set_schedule(ends_at=timezone.now() - timedelta(hours=1))
        resp = self._submit()
        self.assertEqual(resp.status_code, 403)
        self.assertIn('истёк', resp.json()['message'])

    def test_expired_blocks_detail(self):
        self._set_schedule(ends_at=timezone.now() - timedelta(hours=1))
        resp = self.client.get(
            f'/api/quizzes/{self.quiz.id}', **self.patient_headers()
        )
        self.assertEqual(resp.status_code, 403)

    # --- starts_at в прошлом, ends_at в будущем → доступен ---

    def test_active_window_allows_submit(self):
        self._set_schedule(
            starts_at=timezone.now() - timedelta(hours=1),
            ends_at=timezone.now() + timedelta(days=3),
        )
        resp = self._submit()
        self.assertEqual(resp.status_code, 200)

    # --- Список тестов показывает все ---

    def test_quiz_list_includes_upcoming(self):
        """Будущие тесты видны в списке с is_upcoming=True."""
        self._set_schedule(starts_at=timezone.now() + timedelta(days=5))
        resp = self.client.get(
            '/api/patients/me/quizzes', **self.patient_headers()
        )
        self.assertEqual(resp.status_code, 200)
        quizzes = resp.json()
        quiz = next(q for q in quizzes if q['id'] == self.quiz.id)
        self.assertTrue(quiz['is_upcoming'])
        self.assertFalse(quiz['is_available'])

    def test_quiz_list_includes_expired(self):
        """Просроченные тесты видны с is_expired=True."""
        self._set_schedule(ends_at=timezone.now() - timedelta(days=1))
        resp = self.client.get(
            '/api/patients/me/quizzes', **self.patient_headers()
        )
        quiz = next(q for q in resp.json() if q['id'] == self.quiz.id)
        self.assertTrue(quiz['is_expired'])
        self.assertFalse(quiz['is_available'])

    def test_quiz_list_shows_days_until_deadline(self):
        """days_until_deadline корректно считается."""
        self._set_schedule(ends_at=timezone.now() + timedelta(days=2, hours=5))
        resp = self.client.get(
            '/api/patients/me/quizzes', **self.patient_headers()
        )
        quiz = next(q for q in resp.json() if q['id'] == self.quiz.id)
        self.assertEqual(quiz['days_until_deadline'], 2)
        self.assertTrue(quiz['is_available'])

    def test_quiz_list_no_deadline(self):
        """Бессрочный тест — days_until_deadline = null."""
        self._set_schedule(starts_at=None, ends_at=None)
        resp = self.client.get(
            '/api/patients/me/quizzes', **self.patient_headers()
        )
        quiz = next(q for q in resp.json() if q['id'] == self.quiz.id)
        self.assertIsNone(quiz['days_until_deadline'])
        self.assertTrue(quiz['is_available'])
