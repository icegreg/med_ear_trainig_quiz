"""Тесты агрегата статистики пациента: /api/doctors/patients/{id}/stats."""
from datetime import timedelta

from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone

from core.models import (
    AudioCategory,
    AudioFile,
    PatientQuizAssignment,
    Quiz,
    QuizQuestion,
    QuizResult,
)

from .helpers import APITestBase


class PatientStatsTest(APITestBase):
    """Динамика, ошибки по звукам и приверженность."""

    def url(self, patient_id=None):
        return f'/api/doctors/patients/{patient_id or self.patient.id}/stats'

    def _quiz_with_questions(self, title, specs):
        """specs: [(audio_file, correct_answer), ...] → (quiz, [questions])."""
        quiz = Quiz.objects.create(title=title)
        questions = [
            QuizQuestion.objects.create(
                quiz=quiz,
                audio_file=audio,
                text=f'Слышите звук {i}?',
                options=['да', 'нет'],
                correct_answer=correct,
                order=i,
            )
            for i, (audio, correct) in enumerate(specs)
        ]
        return quiz, questions

    def _complete(self, quiz, answers, assigned_at=None, completed_at=None):
        assignment = PatientQuizAssignment.objects.create(
            patient=self.patient,
            quiz=quiz,
            status=PatientQuizAssignment.Status.COMPLETED,
            completed_at=completed_at or timezone.now(),
        )
        if assigned_at:
            # assigned_at — auto_now_add, переопределяем точечно.
            PatientQuizAssignment.objects.filter(id=assignment.id).update(
                assigned_at=assigned_at
            )
            assignment.refresh_from_db()
        score = sum(
            1 for a in answers
            if QuizQuestion.objects.get(id=a['question_id']).correct_answer == a['answer']
        )
        QuizResult.objects.create(
            assignment=assignment, answers=answers, score=score,
        )
        return assignment

    # --- Пустые данные ---

    def test_stats_empty_for_patient_without_results(self):
        resp = self.client.get(self.url(), **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data['dynamics'], [])
        self.assertEqual(data['sound_errors'], [])
        self.assertEqual(data['adherence']['completed'], 0)
        # Базовая фикстура даёт одно назначение в статусе assigned.
        self.assertEqual(data['adherence']['assigned'], 1)
        self.assertIsNone(data['adherence']['avg_completion_days'])

    # --- Динамика ---

    def test_dynamics_percent_and_order(self):
        quiz, questions = self._quiz_with_questions(
            'Квиз 1', [(self.audio, 'да'), (self.audio, 'нет')],
        )
        # 1 из 2 правильно → 50%
        self._complete(quiz, [
            {'question_id': questions[0].id, 'answer': 'да'},
            {'question_id': questions[1].id, 'answer': 'да'},
        ])
        quiz2, questions2 = self._quiz_with_questions(
            'Квиз 2', [(self.audio, 'да')],
        )
        self._complete(quiz2, [{'question_id': questions2[0].id, 'answer': 'да'}])

        data = self.client.get(self.url(), **self.doctor_headers()).json()
        points = data['dynamics']
        self.assertEqual(len(points), 2)
        # Хронологический порядок — график строится слева направо.
        self.assertEqual([p['quiz_title'] for p in points], ['Квиз 1', 'Квиз 2'])
        self.assertEqual(points[0]['score'], 1)
        self.assertEqual(points[0]['total'], 2)
        self.assertEqual(points[0]['percent'], 50.0)
        self.assertEqual(points[1]['percent'], 100.0)

    def test_dynamics_total_is_historical_snapshot(self):
        """Вопрос, добавленный в квиз после сдачи, не должен менять старый %."""
        quiz, questions = self._quiz_with_questions('Квиз', [(self.audio, 'да')])
        self._complete(quiz, [{'question_id': questions[0].id, 'answer': 'да'}])
        QuizQuestion.objects.create(
            quiz=quiz, audio_file=self.audio, text='Новый вопрос',
            options=['да', 'нет'], correct_answer='да', order=99,
        )

        data = self.client.get(self.url(), **self.doctor_headers()).json()
        point = data['dynamics'][0]
        self.assertEqual(point['total'], 1)
        self.assertEqual(point['percent'], 100.0)

    # --- Ошибки по звукам ---

    def test_sound_errors_aggregate_across_quizzes(self):
        category = AudioCategory.objects.create(name='Низкие частоты')
        bad = AudioFile.objects.create(
            title='Плохой звук',
            file=SimpleUploadedFile('bad.wav', b'x'),
            category=category,
        )
        good = AudioFile.objects.create(
            title='Хороший звук', file=SimpleUploadedFile('good.wav', b'x'),
        )
        quiz, questions = self._quiz_with_questions(
            'Квиз', [(bad, 'да'), (good, 'да')],
        )
        self._complete(quiz, [
            {'question_id': questions[0].id, 'answer': 'нет'},  # ошибка на bad
            {'question_id': questions[1].id, 'answer': 'да'},   # верно на good
        ])
        quiz2, questions2 = self._quiz_with_questions('Квиз 2', [(bad, 'да')])
        self._complete(quiz2, [
            {'question_id': questions2[0].id, 'answer': 'нет'},  # снова ошибка на bad
        ])

        data = self.client.get(self.url(), **self.doctor_headers()).json()
        sounds = {s['title']: s for s in data['sound_errors']}
        self.assertEqual(sounds['Плохой звук']['answered'], 2)
        self.assertEqual(sounds['Плохой звук']['errors'], 2)
        self.assertEqual(sounds['Плохой звук']['error_percent'], 100.0)
        self.assertEqual(sounds['Плохой звук']['category'], 'Низкие частоты')
        self.assertEqual(sounds['Хороший звук']['errors'], 0)
        self.assertEqual(sounds['Хороший звук']['error_percent'], 0.0)
        # Самый проблемный звук — первым.
        self.assertEqual(data['sound_errors'][0]['title'], 'Плохой звук')

    def test_sound_errors_survive_soft_deleted_audio(self):
        """Удалённый звук не должен ломать агрегат — он остаётся с пометкой."""
        audio = AudioFile.objects.create(
            title='Удалённый звук', file=SimpleUploadedFile('gone.wav', b'x'),
        )
        quiz, questions = self._quiz_with_questions('Квиз', [(audio, 'да')])
        self._complete(quiz, [{'question_id': questions[0].id, 'answer': 'нет'}])
        audio.delete()  # soft delete

        data = self.client.get(self.url(), **self.doctor_headers()).json()
        self.assertEqual(len(data['sound_errors']), 1)
        entry = data['sound_errors'][0]
        self.assertEqual(entry['title'], 'Удалённый звук')
        self.assertTrue(entry['is_deleted'])
        self.assertEqual(entry['errors'], 1)

    def test_sound_errors_handle_question_without_audio(self):
        quiz, questions = self._quiz_with_questions('Квиз', [(None, 'да')])
        self._complete(quiz, [{'question_id': questions[0].id, 'answer': 'нет'}])

        data = self.client.get(self.url(), **self.doctor_headers()).json()
        entry = data['sound_errors'][0]
        self.assertIsNone(entry['audio_id'])
        self.assertEqual(entry['title'], 'Без звука')
        self.assertEqual(entry['errors'], 1)

    def test_deleted_question_is_skipped_not_fatal(self):
        """Вопрос удалён из квиза: правильный ответ неизвестен — звук не считаем,
        но сам результат остаётся в динамике."""
        quiz, questions = self._quiz_with_questions('Квиз', [(self.audio, 'да')])
        self._complete(quiz, [{'question_id': questions[0].id, 'answer': 'да'}])
        questions[0].delete()

        resp = self.client.get(self.url(), **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(len(data['dynamics']), 1)
        self.assertEqual(data['sound_errors'], [])

    # --- Приверженность ---

    def test_adherence_counts_and_average_lag(self):
        now = timezone.now()
        quiz, questions = self._quiz_with_questions('Квиз', [(self.audio, 'да')])
        # Назначен 10 дней назад, пройден сегодня → лаг 10 дней.
        self._complete(
            quiz,
            [{'question_id': questions[0].id, 'answer': 'да'}],
            assigned_at=now - timedelta(days=10),
            completed_at=now,
        )
        # Просроченное назначение.
        expired_quiz = Quiz.objects.create(title='Просроченный')
        PatientQuizAssignment.objects.create(
            patient=self.patient, quiz=expired_quiz,
            ends_at=now - timedelta(days=1),
        )
        # Ещё не начавшееся.
        upcoming_quiz = Quiz.objects.create(title='Будущий')
        PatientQuizAssignment.objects.create(
            patient=self.patient, quiz=upcoming_quiz,
            starts_at=now + timedelta(days=3),
        )

        data = self.client.get(self.url(), **self.doctor_headers()).json()
        adherence = data['adherence']
        self.assertEqual(adherence['completed'], 1)
        self.assertEqual(adherence['expired'], 1)
        self.assertEqual(adherence['upcoming'], 1)
        # assigned: базовая фикстура + просроченный + будущий.
        self.assertEqual(adherence['assigned'], 3)
        self.assertEqual(adherence['completion_lag_days'], [10])
        self.assertEqual(adherence['avg_completion_days'], 10.0)

    # --- Доступ ---

    def test_stats_requires_auth(self):
        resp = self.client.get(self.url())
        self.assertEqual(resp.status_code, 401)

    def test_stats_of_foreign_patient_is_404(self):
        from django.contrib.auth.models import User

        from core.auth import create_doctor_tokens
        from core.models import Patient

        other_user = User.objects.create_user(username='other', password='x')
        other_patient = Patient.objects.create(user=other_user, doctor=self.doctor2)
        tokens = create_doctor_tokens(self.doctor)
        resp = self.client.get(
            self.url(other_patient.id),
            HTTP_AUTHORIZATION=f'Bearer {tokens["access"]}',
        )
        self.assertEqual(resp.status_code, 404)
