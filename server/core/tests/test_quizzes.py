"""Тесты API квизов."""
import json

from .helpers import APITestBase


class QuizDetailTest(APITestBase):

    def test_get_quiz_detail(self):
        resp = self.client.get(
            f'/api/quizzes/{self.quiz.id}', **self.patient_headers()
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data['title'], 'Тест слуха')
        self.assertEqual(len(data['questions']), 1)
        self.assertEqual(data['questions'][0]['text'], 'Что вы слышите?')

    def test_get_quiz_not_assigned(self):
        """Пациент не может получить квиз, который ему не назначен."""
        from core.models import Quiz
        other_quiz = Quiz.objects.create(title='Другой квиз')
        resp = self.client.get(
            f'/api/quizzes/{other_quiz.id}', **self.patient_headers()
        )
        self.assertEqual(resp.status_code, 404)


class QuizAudioTest(APITestBase):

    def test_get_quiz_audio(self):
        resp = self.client.get(
            f'/api/quizzes/{self.quiz.id}/audio', **self.patient_headers()
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertGreaterEqual(len(data), 1)
        self.assertEqual(data[0]['title'], 'Test Audio')


class QuizSubmitTest(APITestBase):

    def test_submit_correct_answers(self):
        resp = self.client.post(
            f'/api/quizzes/{self.quiz.id}/submit',
            data=json.dumps({
                'answers': [{'question_id': self.question.id, 'answer': 'B'}]
            }),
            content_type='application/json',
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data['status'], 'ok')

    def test_submit_wrong_answers(self):
        resp = self.client.post(
            f'/api/quizzes/{self.quiz.id}/submit',
            data=json.dumps({
                'answers': [{'question_id': self.question.id, 'answer': 'A'}]
            }),
            content_type='application/json',
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 200)

        from core.models import QuizResult
        result = QuizResult.objects.get(assignment=self.assignment)
        self.assertEqual(result.score, 0)

    def test_cannot_submit_twice(self):
        """Повторная отправка запрещена."""
        payload = json.dumps({
            'answers': [{'question_id': self.question.id, 'answer': 'B'}]
        })

        self.client.post(
            f'/api/quizzes/{self.quiz.id}/submit',
            data=payload,
            content_type='application/json',
            **self.patient_headers(),
        )

        resp = self.client.post(
            f'/api/quizzes/{self.quiz.id}/submit',
            data=payload,
            content_type='application/json',
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 403)

    def test_submit_invalid_answer_value(self):
        """Ответ не из допустимых вариантов → 400."""
        resp = self.client.post(
            f'/api/quizzes/{self.quiz.id}/submit',
            data=json.dumps({
                'answers': [{'question_id': self.question.id, 'answer': 'INVALID'}]
            }),
            content_type='application/json',
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 400)

    def test_submit_missing_questions(self):
        """Не все вопросы отвечены → 400."""
        resp = self.client.post(
            f'/api/quizzes/{self.quiz.id}/submit',
            data=json.dumps({'answers': []}),
            content_type='application/json',
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 400)

    def test_submit_unknown_question_id(self):
        """Несуществующий question_id → 400."""
        resp = self.client.post(
            f'/api/quizzes/{self.quiz.id}/submit',
            data=json.dumps({
                'answers': [{'question_id': 99999, 'answer': 'A'}]
            }),
            content_type='application/json',
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 400)

    def test_submit_not_assigned_quiz(self):
        from core.models import Quiz
        other_quiz = Quiz.objects.create(title='Не назначен')
        resp = self.client.post(
            f'/api/quizzes/{other_quiz.id}/submit',
            data=json.dumps({'answers': []}),
            content_type='application/json',
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 404)
