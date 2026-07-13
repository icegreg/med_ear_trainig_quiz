"""Тесты API квизов."""
import json

from django.core.exceptions import ValidationError

from core.models import Quiz, QuizQuestion

from .helpers import APITestBase


class QuestionDefaultAnswerTest(APITestBase):
    """Правильный ответ по умолчанию — «слышу» (да)."""

    def test_correct_answer_defaults_to_yes(self):
        quiz = Quiz.objects.create(title='Тест')
        question = QuizQuestion.objects.create(
            quiz=quiz, audio_file=self.audio, text='Слышите звук?',
        )
        question.refresh_from_db()
        self.assertEqual(question.correct_answer, QuizQuestion.Answer.YES)
        self.assertEqual(question.correct_answer, 'да')
        # Варианты ответа дефолтятся согласованно с правильным.
        self.assertEqual(question.options, ['да', 'нет'])

    def test_correct_answer_can_be_set_to_no(self):
        """Дефолт — не запрет: «не слышу» тоже валидный правильный ответ."""
        quiz = Quiz.objects.create(title='Тест на тишину')
        question = QuizQuestion.objects.create(
            quiz=quiz, audio_file=self.audio, text='Слышите звук?',
            correct_answer=QuizQuestion.Answer.NO,
        )
        question.full_clean()
        self.assertEqual(question.correct_answer, 'нет')

    def test_answer_outside_choices_is_invalid(self):
        """Опечатка вроде «Да» больше не пройдёт валидацию (админка, формы)."""
        quiz = Quiz.objects.create(title='Тест')
        question = QuizQuestion(
            quiz=quiz, audio_file=self.audio, text='Слышите звук?',
            correct_answer='Да',
        )
        with self.assertRaises(ValidationError):
            question.full_clean()


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
