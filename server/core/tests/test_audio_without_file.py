"""Аудио-запись без файла не должна ронять эндпоинты.

Такая запись появляется, если звук завели в админке, но файл не приложили.
Раньше `af.file.url` бросал ValueError и весь ответ падал с 500 — вместе со
всеми остальными, здоровыми звуками.
"""
from core.models import AudioFile, PatientQuizAssignment, Quiz, QuizQuestion

from .helpers import APITestBase


class AudioWithoutFileTest(APITestBase):
    """Списки отдают 200, у битой записи `file` — пустая строка."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        # Звук без файла — рядом со здоровым cls.audio из базовой фикстуры.
        cls.broken = AudioFile.objects.create(title='Гул 500 Гц', file='')
        cls.broken_quiz = Quiz.objects.create(title='Тест с битым звуком')
        cls.broken_quiz.audio_files.add(cls.broken)
        QuizQuestion.objects.create(
            quiz=cls.broken_quiz, audio_file=cls.broken,
            text='Слышите гул?', order=1,
        )
        cls.broken_assignment = PatientQuizAssignment.objects.create(
            patient=cls.patient, quiz=cls.broken_quiz,
        )

    def test_file_url_property_is_empty_string(self):
        self.assertEqual(self.broken.file_url, '')
        self.assertTrue(self.audio.file_url)

    def test_audio_library_lists_both(self):
        resp = self.client.get('/api/doctors/audio-library', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        by_title = {a['title']: a for a in resp.json()}
        self.assertEqual(by_title['Гул 500 Гц']['file'], '')
        self.assertTrue(by_title['Test Audio']['file'])

    def test_doctor_quizzes_list(self):
        resp = self.client.get('/api/doctors/quizzes', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        titles = {q['title'] for q in resp.json()}
        self.assertIn('Тест с битым звуком', titles)

    def test_doctor_quiz_audio(self):
        resp = self.client.get(
            f'/api/doctors/quizzes/{self.broken_quiz.id}/audio',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()[0]['file'], '')

    def test_patient_quiz_audio(self):
        """Пациентское приложение тоже не должно падать."""
        resp = self.client.get(
            f'/api/quizzes/{self.broken_quiz.id}/audio',
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()[0]['file'], '')

    def test_patient_profile_with_fileless_starting_sound(self):
        """starting_sound без файла → url = None, а не 500."""
        self.patient.starting_sound = self.broken
        self.patient.save(update_fields=['starting_sound'])

        resp = self.client.get('/api/patients/me', **self.patient_headers())
        self.assertEqual(resp.status_code, 200)
        self.assertIsNone(resp.json()['starting_sound_url'])

        resp = self.client.get('/api/doctors/me/patients', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        me = next(p for p in resp.json() if p['id'] == self.patient.id)
        self.assertIsNone(me['starting_sound_url'])
