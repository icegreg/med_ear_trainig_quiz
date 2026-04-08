"""
Генератор тестовых данных: врачи, пациенты, квизы.

Примеры:
  # Дефолтные параметры (5 врачей, 5 пациентов/врач, 3-6 тестов, 3-10 вопросов)
  python manage.py generate_test_data

  # Кастомные параметры
  python manage.py generate_test_data --doctors 3 --patients-per-doctor 10 \
      --quizzes-min 2 --quizzes-max 8 --questions-min 5 --questions-max 15

  # Добавить тесты существующим пациентам
  python manage.py generate_test_data --existing --patients patient1,patient2

  # Добавить тесты всем существующим пациентам
  python manage.py generate_test_data --existing

  # Указать папку для credentials-файлов
  python manage.py generate_test_data --output-dir /tmp/creds
"""

import csv
import os
import random
import string

from django.contrib.auth.models import User
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.management.base import BaseCommand

from core.models import (
    AudioFile,
    Doctor,
    Patient,
    PatientQuizAssignment,
    Quiz,
    QuizQuestion,
)

FIRST_NAMES = [
    'Александр', 'Дмитрий', 'Максим', 'Сергей', 'Андрей',
    'Алексей', 'Артём', 'Илья', 'Кирилл', 'Михаил',
    'Анна', 'Мария', 'Елена', 'Ольга', 'Татьяна',
    'Наталья', 'Ирина', 'Светлана', 'Екатерина', 'Юлия',
]

LAST_NAMES = [
    'Иванов', 'Смирнов', 'Кузнецов', 'Попов', 'Васильев',
    'Петров', 'Соколов', 'Михайлов', 'Новиков', 'Фёдоров',
    'Морозов', 'Волков', 'Алексеев', 'Лебедев', 'Семёнов',
]

PATRONYMICS = [
    'Александрович', 'Дмитриевич', 'Сергеевич', 'Андреевич',
    'Михайлович', 'Алексеевич', 'Иванович', 'Петрович',
]

CLINICS = [
    'Городская поликлиника №1', 'Областная больница',
    'Медцентр «Здоровье»', 'Клиника «Слух+»',
    'НМИЦ оториноларингологии', '',
]

QUESTION_TEMPLATES = [
    'Вы слышите звук?',
    'Звук стал тише?',
    'Вы слышите звук в правом ухе?',
    'Вы слышите звук в левом ухе?',
    'Звук стал громче?',
    'Вы слышите два звука одновременно?',
    'Звук прерывистый?',
    'Вы слышите низкий тон?',
    'Вы слышите высокий тон?',
    'Звук изменился?',
    'Вы слышите шум?',
    'Звук одинаковый в обоих ушах?',
    'Вы слышите щелчок?',
    'Звук пульсирующий?',
    'Вы различаете два разных тона?',
]

QUIZ_TITLES = [
    'Тест слуха — базовый',
    'Тест на восприятие частот',
    'Тест на различение громкости',
    'Тест на латерализацию звука',
    'Тест на восприятие речи',
    'Аудиометрия — скрининг',
    'Тест на тиннитус',
    'Тест на восприятие шёпотной речи',
]


def random_password(length=10):
    chars = string.ascii_letters + string.digits
    return ''.join(random.choices(chars, k=length))


def get_or_create_audio_files(count=5):
    """Возвращает существующие аудио-файлы. Если их нет — генерирует через generate_audio_samples."""
    existing = list(AudioFile.objects.all())
    if len(existing) >= count:
        return existing[:count]

    if not existing:
        from django.core.management import call_command
        call_command('generate_audio_samples')
        existing = list(AudioFile.objects.all())

    if len(existing) >= count:
        return existing[:count]

    # Fallback — добить заглушками если всё ещё мало
    for i in range(len(existing), count):
        af = AudioFile.objects.create(
            title=f'Тестовый тон {i + 1}',
            file=SimpleUploadedFile(
                f'tone_{i + 1}.wav', b'RIFF' + b'\x00' * 100
            ),
            duration_seconds=random.randint(2, 5),
        )
        existing.append(af)
    return existing


class Command(BaseCommand):
    help = 'Генерация тестовых данных: врачи, пациенты, квизы'

    def add_arguments(self, parser):
        parser.add_argument(
            '--doctors', type=int, default=5,
            help='Количество врачей (по умолчанию: 5)',
        )
        parser.add_argument(
            '--patients-per-doctor', type=int, default=5,
            help='Среднее кол-во пациентов на врача (по умолчанию: 5)',
        )
        parser.add_argument(
            '--quizzes-min', type=int, default=3,
            help='Мин. кол-во тестов на пациента (по умолчанию: 3)',
        )
        parser.add_argument(
            '--quizzes-max', type=int, default=6,
            help='Макс. кол-во тестов на пациента (по умолчанию: 6)',
        )
        parser.add_argument(
            '--questions-min', type=int, default=3,
            help='Мин. кол-во вопросов в тесте (по умолчанию: 3)',
        )
        parser.add_argument(
            '--questions-max', type=int, default=10,
            help='Макс. кол-во вопросов в тесте (по умолчанию: 10)',
        )
        parser.add_argument(
            '--existing', action='store_true',
            help='Использовать существующих пациентов и врачей, '
                 'только добавить новые тесты',
        )
        parser.add_argument(
            '--patients', type=str, default='',
            help='Список username пациентов через запятую '
                 '(используется с --existing)',
        )
        parser.add_argument(
            '--output-dir', type=str, default='.',
            help='Папка для сохранения credentials-файлов (по умолчанию: .)',
        )

    def handle(self, *args, **options):
        audio_files = get_or_create_audio_files(10)

        if options['existing']:
            self._add_quizzes_to_existing(options, audio_files)
        else:
            self._generate_all(options, audio_files)

    def _generate_all(self, options, audio_files):
        output_dir = options['output_dir']
        doctor_creds = []
        patient_creds = []

        # Генерация врачей
        self.stdout.write(self.style.MIGRATE_HEADING('Создание врачей...'))
        doctors = []
        for i in range(options['doctors']):
            first = random.choice(FIRST_NAMES)
            last = random.choice(LAST_NAMES)
            patr = random.choice(PATRONYMICS)
            clinic = random.choice(CLINICS)
            username = f'doctor_{i + 1}'
            password = random_password()

            user = User.objects.create_user(
                username=username, password=password,
                first_name=first, last_name=last,
                email=f'{username}@medear.test',
            )
            doctor = Doctor.objects.create(
                user=user, last_name=last, first_name=first,
                patronymic=patr, clinic=clinic,
            )
            doctors.append(doctor)
            doctor_creds.append({
                'username': username,
                'password': password,
                'doctor_id': str(doctor.id),
                'name': f'{last} {first} {patr}',
                'clinic': clinic,
            })
            self.stdout.write(f'  {doctor} ({username})')

        # Генерация пациентов
        self.stdout.write(self.style.MIGRATE_HEADING('Создание пациентов...'))
        patients = []
        for i in range(options['doctors'] * options['patients_per_doctor']):
            username = f'patient_{i + 1}'
            password = random_password()
            doctor = random.choice(doctors)

            user = User.objects.create_user(
                username=username, password=password,
            )
            patient = Patient.objects.create(user=user, doctor=doctor)
            patients.append(patient)
            patient_creds.append({
                'username': username,
                'password': password,
                'patient_id': patient.id,
                'doctor': str(doctor),
            })
            self.stdout.write(f'  {patient} → {doctor}')

        # Генерация квизов и назначений
        self.stdout.write(self.style.MIGRATE_HEADING('Создание тестов...'))
        total_quizzes = 0
        for patient in patients:
            n_quizzes = random.randint(
                options['quizzes_min'], options['quizzes_max']
            )
            for _ in range(n_quizzes):
                quiz = self._create_quiz(options, audio_files)
                PatientQuizAssignment.objects.create(
                    patient=patient, quiz=quiz,
                )
                total_quizzes += 1
            self.stdout.write(
                f'  {patient.user.username}: {n_quizzes} тестов назначено'
            )

        # Сохранение credentials
        doctors_file = os.path.join(output_dir, 'doctors_credentials.csv')
        patients_file = os.path.join(output_dir, 'patients_credentials.csv')

        self._write_csv(doctors_file, doctor_creds,
                        ['username', 'password', 'doctor_id', 'name', 'clinic'])
        self._write_csv(patients_file, patient_creds,
                        ['username', 'password', 'patient_id', 'doctor'])

        self.stdout.write(self.style.SUCCESS(
            f'\nГотово: {len(doctors)} врачей, {len(patients)} пациентов, '
            f'{total_quizzes} тестов'
        ))
        self.stdout.write(f'Credentials врачей:   {doctors_file}')
        self.stdout.write(f'Credentials пациентов: {patients_file}')

    def _add_quizzes_to_existing(self, options, audio_files):
        patient_usernames = [
            u.strip() for u in options['patients'].split(',') if u.strip()
        ]

        if patient_usernames:
            patients = list(
                Patient.objects.filter(
                    user__username__in=patient_usernames
                ).select_related('user')
            )
            not_found = set(patient_usernames) - {
                p.user.username for p in patients
            }
            if not_found:
                self.stderr.write(self.style.ERROR(
                    f'Пациенты не найдены: {", ".join(not_found)}'
                ))
        else:
            patients = list(Patient.objects.select_related('user').all())

        if not patients:
            self.stderr.write(self.style.ERROR('Нет пациентов для обновления'))
            return

        self.stdout.write(self.style.MIGRATE_HEADING(
            'Добавление тестов существующим пациентам...'
        ))

        total_quizzes = 0
        for patient in patients:
            n_quizzes = random.randint(
                options['quizzes_min'], options['quizzes_max']
            )
            added = 0
            for _ in range(n_quizzes):
                quiz = self._create_quiz(options, audio_files)
                if not PatientQuizAssignment.objects.filter(
                    patient=patient, quiz=quiz
                ).exists():
                    PatientQuizAssignment.objects.create(
                        patient=patient, quiz=quiz,
                    )
                    added += 1
            total_quizzes += added
            self.stdout.write(
                f'  {patient.user.username}: +{added} тестов'
            )

        self.stdout.write(self.style.SUCCESS(
            f'\nГотово: обновлено {len(patients)} пациентов, '
            f'добавлено {total_quizzes} тестов'
        ))

    def _create_quiz(self, options, audio_files):
        title = random.choice(QUIZ_TITLES) + f' #{Quiz.objects.count() + 1}'
        quiz = Quiz.objects.create(
            title=title,
            description=f'Автоматически сгенерированный тест',
        )

        selected_audio = random.sample(
            audio_files, k=min(3, len(audio_files))
        )
        quiz.audio_files.set(selected_audio)

        n_questions = random.randint(
            options['questions_min'], options['questions_max']
        )
        questions = random.sample(
            QUESTION_TEMPLATES, k=min(n_questions, len(QUESTION_TEMPLATES))
        )
        # Добить если нужно больше
        while len(questions) < n_questions:
            questions.append(random.choice(QUESTION_TEMPLATES))

        for order, text in enumerate(questions, start=1):
            QuizQuestion.objects.create(
                quiz=quiz,
                audio_file=random.choice(audio_files),
                text=text,
                options=['да', 'нет'],
                correct_answer=random.choice(['да', 'нет']),
                order=order,
            )

        return quiz

    def _write_csv(self, path, rows, fieldnames):
        with open(path, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)
