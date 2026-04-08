"""Тесты soft delete для AudioFile и QuizResult."""
import json

from django.contrib.auth.models import User
from django.core.management import call_command
from django.test import TestCase

from .helpers import APITestBase
from core.models import AudioFile, QuizResult


class AudioFileSoftDeleteTest(APITestBase):

    def test_delete_marks_as_deleted(self):
        """Удаление AudioFile — soft delete, запись остаётся в БД."""
        self.audio.delete(user=self.doctor_user)
        self.audio.refresh_from_db()
        self.assertTrue(self.audio.is_deleted)
        self.assertIsNotNone(self.audio.deleted_at)
        self.assertEqual(self.audio.deleted_by, self.doctor_user)

    def test_soft_deleted_not_in_default_queryset(self):
        """Soft-deleted файлы не видны через objects."""
        self.audio.delete()
        self.assertFalse(AudioFile.objects.filter(id=self.audio.id).exists())

    def test_soft_deleted_visible_in_all_objects(self):
        """Soft-deleted файлы видны через all_objects."""
        self.audio.delete()
        self.assertTrue(AudioFile.all_objects.filter(id=self.audio.id).exists())

    def test_restore(self):
        """Восстановление soft-deleted файла."""
        self.audio.delete(user=self.doctor_user)
        self.audio.restore()
        self.audio.refresh_from_db()
        self.assertFalse(self.audio.is_deleted)
        self.assertIsNone(self.audio.deleted_at)
        self.assertIsNone(self.audio.deleted_by)
        self.assertTrue(AudioFile.objects.filter(id=self.audio.id).exists())

    def test_hard_delete_removes_from_db(self):
        """hard_delete физически удаляет запись."""
        audio_id = self.audio.id
        self.audio.hard_delete()
        self.assertFalse(AudioFile.all_objects.filter(id=audio_id).exists())

    def test_api_does_not_return_deleted_audio(self):
        """API не возвращает soft-deleted аудио-файлы."""
        self.audio.delete()
        resp = self.client.get(
            f'/api/quizzes/{self.quiz.id}/audio',
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        audio_ids = [a['id'] for a in resp.json()]
        self.assertNotIn(self.audio.id, audio_ids)


class QuizResultSoftDeleteTest(APITestBase):

    def _submit_quiz(self):
        return self.client.post(
            f'/api/quizzes/{self.quiz.id}/submit',
            data=json.dumps({
                'answers': [{'question_id': self.question.id, 'answer': 'B'}]
            }),
            content_type='application/json',
            **self.patient_headers(),
        )

    def test_delete_marks_result_as_deleted(self):
        """Удаление QuizResult — soft delete."""
        self._submit_quiz()
        result = QuizResult.objects.get(assignment=self.assignment)
        result.delete(user=self.doctor_user)
        result.refresh_from_db()
        self.assertTrue(result.is_deleted)
        self.assertIsNotNone(result.deleted_at)

    def test_soft_deleted_result_not_in_default_queryset(self):
        self._submit_quiz()
        result = QuizResult.objects.get(assignment=self.assignment)
        result.delete()
        self.assertFalse(QuizResult.objects.filter(id=result.id).exists())

    def test_soft_deleted_result_not_in_api(self):
        """API не возвращает soft-deleted результаты."""
        self._submit_quiz()
        result = QuizResult.objects.get(assignment=self.assignment)
        result.delete()
        resp = self.client.get('/api/patients/me/results', **self.patient_headers())
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.json()), 0)

    def test_hard_delete_result(self):
        self._submit_quiz()
        result = QuizResult.objects.get(assignment=self.assignment)
        result_id = result.id
        result.hard_delete()
        self.assertFalse(QuizResult.all_objects.filter(id=result_id).exists())


class PurgeAudioFileCommandTest(TestCase):

    def test_purge_deletes_file(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        audio = AudioFile.all_objects.create(
            title='To purge',
            file=SimpleUploadedFile('purge.wav', b'data'),
        )
        audio_id = audio.id
        call_command('purge_audio_file', str(audio_id), '--force')
        self.assertFalse(AudioFile.all_objects.filter(id=audio_id).exists())

    def test_purge_nonexistent_raises_error(self):
        from django.core.management.base import CommandError
        with self.assertRaises(CommandError):
            call_command('purge_audio_file', '999999', '--force')
