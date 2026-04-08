"""
Физическое удаление одного аудио-файла по ID.
Удаляет файл с диска и запись из БД. Один файл за раз.

Примеры:
  python manage.py purge_audio_file 42
  python manage.py purge_audio_file 42 --force  # без подтверждения
"""

from django.core.management.base import BaseCommand, CommandError

from core.models import AudioFile


class Command(BaseCommand):
    help = 'Физическое удаление одного аудио-файла (с диска и из БД)'

    def add_arguments(self, parser):
        parser.add_argument(
            'audio_id', type=int,
            help='ID аудио-файла для удаления',
        )
        parser.add_argument(
            '--force', action='store_true',
            help='Удалить без подтверждения',
        )

    def handle(self, *args, **options):
        audio_id = options['audio_id']

        try:
            audio = AudioFile.all_objects.get(id=audio_id)
        except AudioFile.DoesNotExist:
            raise CommandError(f'Аудио-файл с ID={audio_id} не найден.')

        self.stdout.write(f'Файл:     {audio.title}')
        self.stdout.write(f'Путь:     {audio.file.name}')
        self.stdout.write(f'Загружен: {audio.uploaded_at}')
        if audio.is_deleted:
            self.stdout.write(f'Помечен как удалённый: {audio.deleted_at}')
        else:
            self.stdout.write(self.style.WARNING(
                'ВНИМАНИЕ: файл НЕ помечен как удалённый!'
            ))

        # Проверяем ссылки
        quiz_count = audio.quizzes.count()
        question_count = audio.questions.count()
        if quiz_count or question_count:
            self.stdout.write(self.style.WARNING(
                f'Файл используется: {quiz_count} квизов, {question_count} вопросов'
            ))

        if not options['force']:
            confirm = input('\nФИЗИЧЕСКИ удалить файл с диска и из БД? [y/N]: ')
            if confirm.lower() != 'y':
                self.stdout.write('Отменено.')
                return

        file_path = audio.file.name
        audio.hard_delete()
        self.stdout.write(self.style.SUCCESS(
            f'Удалено: ID={audio_id}, файл={file_path}'
        ))
