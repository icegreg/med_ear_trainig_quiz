"""Общие хелперы для тестов API."""
from django.contrib.auth.models import User
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase

from core.auth import create_doctor_tokens
from core.models import (
    AudioFile,
    DeviceToken,
    Doctor,
    Patient,
    PatientQuizAssignment,
    Quiz,
    QuizQuestion,
)


class APITestBase(TestCase):
    """Базовый класс с фикстурами для тестов API."""

    @classmethod
    def setUpTestData(cls):
        # Врач
        cls.doctor_user = User.objects.create_user(
            username='doctor1', password='docpass123',
            first_name='Иван', last_name='Петров',
            email='doc@test.com',
        )
        cls.doctor = Doctor.objects.create(
            user=cls.doctor_user,
            last_name='Петров',
            first_name='Иван',
            patronymic='Сергеевич',
            clinic='Клиника №1',
        )

        # Второй врач (для transfer)
        cls.doctor_user2 = User.objects.create_user(
            username='doctor2', password='docpass456',
        )
        cls.doctor2 = Doctor.objects.create(
            user=cls.doctor_user2,
            last_name='Сидоров',
            first_name='Пётр',
        )

        # Пациент
        cls.patient_user = User.objects.create_user(
            username='patient1', password='patpass123',
        )
        cls.patient = Patient.objects.create(
            user=cls.patient_user, doctor=cls.doctor,
        )

        # Device token
        cls.device_token = DeviceToken.objects.create(patient=cls.patient)

        # Аудио
        cls.audio = AudioFile.objects.create(
            title='Test Audio',
            file=SimpleUploadedFile('test.wav', b'fake-audio-data'),
            duration_seconds=10,
        )

        # Квиз с вопросом
        cls.quiz = Quiz.objects.create(title='Тест слуха', description='Описание')
        cls.quiz.audio_files.add(cls.audio)
        cls.question = QuizQuestion.objects.create(
            quiz=cls.quiz,
            audio_file=cls.audio,
            text='Что вы слышите?',
            options=['A', 'B', 'C'],
            correct_answer='B',
            order=1,
        )

        # Назначение квиза
        cls.assignment = PatientQuizAssignment.objects.create(
            patient=cls.patient, quiz=cls.quiz,
        )

    def patient_headers(self):
        return {'HTTP_AUTHORIZATION': f'Bearer {self.device_token.token}'}

    def doctor_headers(self):
        tokens = create_doctor_tokens(self.doctor)
        return {'HTTP_AUTHORIZATION': f'Bearer {tokens["access"]}'}
