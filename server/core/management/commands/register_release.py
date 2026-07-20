"""
Регистрация собранного APK в реестре релизов (Kaiten #67040240).

Вызывается сборочным сервисом после `flutter build apk` на стенде.

Примеры:
  # Зарегистрировать APK и сразу сделать его дефолтным
  python manage.py register_release \
      --apk build/app/outputs/apk/prod/release/tnoise-prod-release-0.10.0+7.apk \
      --version-name 0.10.0 --version-code 7 --commit $GIT_SHA --set-default

  # Просто добавить в реестр, не трогая дефолт
  python manage.py register_release --apk out.apk --version-name 0.6.0 --version-code 2
"""
import os

from django.core.files import File
from django.core.management.base import BaseCommand, CommandError

from core.models import Release


class Command(BaseCommand):
    help = 'Зарегистрировать собранный APK в реестре релизов.'

    def add_arguments(self, parser):
        parser.add_argument('--apk', required=True, help='Путь к .apk файлу')
        parser.add_argument(
            '--version-name', required=True, help='versionName, напр. 0.6.0'
        )
        parser.add_argument(
            '--version-code', required=True, type=int, help='versionCode, напр. 2'
        )
        parser.add_argument('--commit', default='', help='Git commit SHA')
        parser.add_argument('--notes', default='', help='Описание релиза')
        parser.add_argument(
            '--set-default', action='store_true',
            help='Сделать этот релиз дефолтным (ссылка latest.apk).',
        )

    def handle(self, *args, **opts):
        apk_path = opts['apk']
        if not os.path.isfile(apk_path):
            raise CommandError(f'APK не найден: {apk_path}')

        version_name = opts['version_name']
        version_code = opts['version_code']

        if Release.objects.filter(
            version_name=version_name, version_code=version_code
        ).exists():
            raise CommandError(
                f'Релиз {version_name}+{version_code} уже зарегистрирован.'
            )

        release = Release(
            version_name=version_name,
            version_code=version_code,
            commit_sha=opts['commit'],
            notes=opts['notes'],
            file_size=os.path.getsize(apk_path),
        )
        # Имя, под которым APK ложится в хранилище и раздаётся пользователю.
        # Flavor в имя не входит: реестр привязан к стенду, у preprod и prod
        # свои БД, поэтому flavor константный и в модели Release не хранится.
        # Дефис, а не '+': Django strip'ает '+' из имени файла в хранилище.
        filename = f'tnoise-{version_name}-{version_code}.apk'
        with open(apk_path, 'rb') as fh:
            release.apk.save(filename, File(fh), save=True)

        if opts['set_default']:
            release.set_default()

        self.stdout.write(self.style.SUCCESS(
            f'Зарегистрирован релиз {release} '
            f'(default={release.is_default}) → {release.download_url}'
        ))
