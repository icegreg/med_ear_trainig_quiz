"""Тесты разбора результата по вопросам: /api/doctors/results/{assignment_id}."""
from django.contrib.auth.models import User
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone

from core.auth import create_doctor_tokens
from core.models import (
    AudioFile,
    Patient,
    PatientQuizAssignment,
    Quiz,
    QuizQuestion,
    QuizResult,
)

from .helpers import APITestBase


class ResultBreakdownTest(APITestBase):

    def setUp(self):
        self.audio = AudioFile.objects.create(
            title='Гул 500 Гц', file=SimpleUploadedFile('gul.wav', b'x'),
        )
        self.quiz = Quiz.objects.create(title='Проверка слуха')
        self.q1 = QuizQuestion.objects.create(
            quiz=self.quiz, audio_file=self.audio, text='Слышите гул?',
            options=['да', 'нет'], correct_answer='да', order=1,
        )
        self.q2 = QuizQuestion.objects.create(
            quiz=self.quiz, audio_file=None, text='Слышите тишину?',
            options=['да', 'нет'], correct_answer='нет', order=2,
        )
        self.assignment = PatientQuizAssignment.objects.create(
            patient=self.patient, quiz=self.quiz,
            status=PatientQuizAssignment.Status.COMPLETED,
            completed_at=timezone.now(),
        )
        self.result = QuizResult.objects.create(
            assignment=self.assignment,
            answers=[
                {'question_id': self.q1.id, 'answer': 'нет'},  # ошибка
                {'question_id': self.q2.id, 'answer': 'нет'},  # верно
            ],
            score=1,
        )

    def url(self, assignment_id=None):
        return f'/api/doctors/results/{assignment_id or self.assignment.id}'

    def test_breakdown_joins_questions_answers_and_audio(self):
        resp = self.client.get(self.url(), **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()

        self.assertEqual(data['quiz_title'], 'Проверка слуха')
        self.assertEqual(data['score'], 1)
        self.assertEqual(data['total'], 2)
        self.assertEqual(data['percent'], 50.0)

        first, second = data['questions']
        # Порядок — по QuizQuestion.order, а не по порядку в answers.
        self.assertEqual(first['text'], 'Слышите гул?')
        self.assertEqual(first['audio_title'], 'Гул 500 Гц')
        self.assertTrue(first['audio_url'])
        self.assertEqual(first['patient_answer'], 'нет')
        self.assertEqual(first['correct_answer'], 'да')
        self.assertFalse(first['is_correct'])

        self.assertEqual(second['text'], 'Слышите тишину?')
        self.assertIsNone(second['audio_id'])
        self.assertIsNone(second['audio_title'])
        self.assertTrue(second['is_correct'])

    def test_breakdown_orders_by_question_order(self):
        # Ответы приходят в обратном порядке — разбор всё равно по order.
        self.result.answers = [
            {'question_id': self.q2.id, 'answer': 'нет'},
            {'question_id': self.q1.id, 'answer': 'да'},
        ]
        self.result.save(update_fields=['answers'])

        data = self.client.get(self.url(), **self.doctor_headers()).json()
        self.assertEqual(
            [q['question_id'] for q in data['questions']], [self.q1.id, self.q2.id],
        )

    def test_breakdown_with_soft_deleted_audio(self):
        self.audio.delete()  # soft delete

        data = self.client.get(self.url(), **self.doctor_headers()).json()
        first = data['questions'][0]
        self.assertEqual(first['audio_title'], 'Гул 500 Гц')
        self.assertTrue(first['audio_is_deleted'])
        # Строка не должна исчезнуть — результат теста неизменен.
        self.assertEqual(first['patient_answer'], 'нет')

    def test_breakdown_with_deleted_question(self):
        """Вопрос удалён из квиза: ответ пациента сохраняем, сверить не с чем."""
        self.q1.delete()

        resp = self.client.get(self.url(), **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(len(data['questions']), 2)

        # Удалённые вопросы уходят в конец.
        last = data['questions'][-1]
        self.assertTrue(last['question_deleted'])
        self.assertIsNone(last['is_correct'])
        self.assertIsNone(last['correct_answer'])
        self.assertEqual(last['patient_answer'], 'нет')

    def test_breakdown_of_foreign_patient_is_404(self):
        other_user = User.objects.create_user(username='other', password='x')
        other_patient = Patient.objects.create(user=other_user, doctor=self.doctor2)
        quiz = Quiz.objects.create(title='Чужой')
        assignment = PatientQuizAssignment.objects.create(
            patient=other_patient, quiz=quiz,
            status=PatientQuizAssignment.Status.COMPLETED,
        )
        QuizResult.objects.create(assignment=assignment, answers=[], score=0)

        tokens = create_doctor_tokens(self.doctor)
        resp = self.client.get(
            self.url(assignment.id),
            HTTP_AUTHORIZATION=f'Bearer {tokens["access"]}',
        )
        self.assertEqual(resp.status_code, 404)

    def test_breakdown_of_soft_deleted_result_is_404(self):
        self.result.delete()  # soft delete
        resp = self.client.get(self.url(), **self.doctor_headers())
        self.assertEqual(resp.status_code, 404)

    def test_breakdown_requires_auth(self):
        resp = self.client.get(self.url())
        self.assertEqual(resp.status_code, 401)
