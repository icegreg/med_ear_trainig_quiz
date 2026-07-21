"""Авторегистрация собранного APK из media/releases/incoming/ (Kaiten #67652021).

Сборочный сервис apk-build кладёт файл `tnoise-<flavor>-release-<vName>+<vCode>.apk`
в общий том, а эта команда подхватывает его и регистрирует в реестре релизов —
версию берёт из имени файла, ручной ввод не нужен.

Отличие от register_release: та требует версию аргументами и падает на дубле
(её вызывает деплой стенда); эта — выводит версию из имени и идемпотентна
(повторный прогон той же версии просто пропускает).

Примеры:
  # Зарегистрировать свежий preprod-APK и сделать дефолтным
  python manage.py register_incoming --flavor preprod --set-default --commit $GIT_SHA

  # Любой свежий APK из incoming/, без дефолта, с удалением исходника
  python manage.py register_incoming --cleanup
"""
import os
import re

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from core.models import Release

# tnoise-<flavor>-<buildType>-<versionName>+<versionCode>.apk
# (см. patient_app/android/app/build.gradle, outputFileName). versionName может
# содержать точки, но не '+'; versionCode — только цифры.
_APK_RE = re.compile(
    r'^tnoise-(?P<flavor>[^-]+)-(?P<buildtype>[^-]+)-'
    r'(?P<version_name>[^+]+)\+(?P<version_code>\d+)\.apk$'
)


class Command(BaseCommand):
    help = 'Зарегистрировать APK из media/releases/incoming/ (версия из имени файла).'

    def add_arguments(self, parser):
        parser.add_argument(
            '--flavor', default='',
            help='Брать только APK этого flavor (напр. preprod). Пусто — любой.',
        )
        parser.add_argument('--commit', default='', help='Git commit SHA')
        parser.add_argument('--notes', default='', help='Описание релиза')
        parser.add_argument(
            '--set-default', action='store_true',
            help='Сделать этот релиз дефолтным (ссылка latest.apk).',
        )
        parser.add_argument(
            '--cleanup', action='store_true',
            help='Удалить исходный файл из incoming/ после успешной регистрации.',
        )

    def handle(self, *args, **opts):
        incoming = os.path.join(settings.MEDIA_ROOT, 'releases', 'incoming')
        if not os.path.isdir(incoming):
            raise CommandError(f'Нет каталога incoming: {incoming}')

        flavor = opts['flavor']
        candidates = []
        for name in os.listdir(incoming):
            m = _APK_RE.match(name)
            if not m:
                continue
            if flavor and m.group('flavor') != flavor:
                continue
            candidates.append((name, m))

        if not candidates:
            where = f' (flavor={flavor})' if flavor else ''
            raise CommandError(f'В incoming/ нет подходящих tnoise-*.apk{where}.')

        # Самый свежий по mtime. Если после фильтра по flavor осталось несколько
        # РАЗНЫХ версий — это неоднозначность, не регистрируем наугад.
        versions = {(m.group('version_name'), m.group('version_code'))
                    for _, m in candidates}
        if len(versions) > 1:
            names = ', '.join(sorted(n for n, _ in candidates))
            raise CommandError(
                'В incoming/ несколько разных версий — уточните --flavor или '
                f'оставьте один файл. Найдено: {names}'
            )

        name, m = max(
            candidates,
            key=lambda c: os.path.getmtime(os.path.join(incoming, c[0])),
        )
        apk_path = os.path.join(incoming, name)
        version_name = m.group('version_name')
        version_code = int(m.group('version_code'))

        if Release.objects.filter(
            version_name=version_name, version_code=version_code
        ).exists():
            self.stdout.write(self.style.WARNING(
                f'Релиз {version_name}+{version_code} уже зарегистрирован — пропуск.'
            ))
            if opts['cleanup']:
                os.remove(apk_path)
                self.stdout.write(f'Удалён из incoming: {name}')
            return

        release = Release.create_from_apk(
            apk_path, version_name, version_code,
            commit=opts['commit'], notes=opts['notes'],
            set_default=opts['set_default'],
        )

        self.stdout.write(self.style.SUCCESS(
            f'Зарегистрирован релиз {release} '
            f'(default={release.is_default}) → {release.download_url}'
        ))

        if opts['cleanup']:
            os.remove(apk_path)
            self.stdout.write(f'Удалён из incoming: {name}')
