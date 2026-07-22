"""
Регистрация собранного APK в реестре релизов (Kaiten #67040240).

Вызывается сборочным сервисом / деплоем стенда после `flutter build apk`.

Реестр хранит одну запись на версию (`version_name`) и падает, если версия уже
зарегистрирована (для локалки/пересборок есть идемпотентная `register_incoming`).

Аргументы `--version-code`, `--commit`, `--notes` больше не используются (реестр
эти поля не хранит, Kaiten #67689761), но принимаются и игнорируются, чтобы не
ломать существующие вызовы деплоя стендов.

Примеры:
  # Зарегистрировать APK и сразу сделать его дефолтным
  python manage.py register_release \
      --apk build/app/outputs/apk/prod/release/tnoise-prod-release-0.10.0+7.apk \
      --version-name 0.10.0 --set-default

  # Просто добавить в реестр, не трогая дефолт
  python manage.py register_release --apk out.apk --version-name 0.6.0
"""
import os

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
            '--set-default', action='store_true',
            help='Сделать этот релиз дефолтным (ссылка latest.apk).',
        )
        # Устаревшие: реестр их не хранит, принимаем ради совместимости с деплоем.
        parser.add_argument('--version-code', help='(не используется)')
        parser.add_argument('--commit', help='(не используется)')
        parser.add_argument('--notes', help='(не используется)')

    def handle(self, *args, **opts):
        apk_path = opts['apk']
        if not os.path.isfile(apk_path):
            raise CommandError(f'APK не найден: {apk_path}')

        version_name = opts['version_name']

        if Release.objects.filter(version_name=version_name).exists():
            raise CommandError(
                f'Релиз {version_name} уже зарегистрирован.'
            )

        release = Release.create_from_apk(
            apk_path, version_name, set_default=opts['set_default'],
        )

        self.stdout.write(self.style.SUCCESS(
            f'Зарегистрирован релиз {release} '
            f'(default={release.is_default}) → {release.download_url}'
        ))
