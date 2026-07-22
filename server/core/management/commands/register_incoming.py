"""Авторегистрация собранного APK из media/releases/incoming/ (Kaiten #67652021).

Сборочный сервис apk-build кладёт файл `tnoise-<flavor>-release-<vName>+<vCode>.apk`
в общий том, а эта команда подхватывает его и регистрирует в реестре релизов —
версию берёт из имени файла, ручной ввод не нужен.

Реестр хранит одну запись на версию (`version_name`, Kaiten #67689761). Повторная
регистрация той же версии (пересборка) **заменяет** прежний релиз, сохраняя статус
дефолтного, — реестру нужен только последний APK каждой версии.

Аргументы `--commit`/`--notes` больше не используются (реестр их не хранит), но
принимаются и игнорируются ради совместимости.

Примеры:
  # Зарегистрировать свежий preprod-APK и сделать дефолтным
  python manage.py register_incoming --flavor preprod --set-default

  # Любой свежий APK из incoming/, с удалением исходника
  python manage.py register_incoming --cleanup
"""
import os
import re

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from core.models import Release

# tnoise-<flavor>-<buildType>-<versionName>+<versionCode>.apk
# (см. patient_app/android/app/build.gradle, outputFileName). versionCode из
# имени берём только для его удаления при сравнении — в реестре он не хранится.
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
        parser.add_argument(
            '--set-default', action='store_true',
            help='Сделать этот релиз дефолтным (ссылка latest.apk).',
        )
        parser.add_argument(
            '--cleanup', action='store_true',
            help='Удалить исходный файл из incoming/ после успешной регистрации.',
        )
        # Устаревшие: реестр их не хранит, принимаем ради совместимости.
        parser.add_argument('--commit', help='(не используется)')
        parser.add_argument('--notes', help='(не используется)')

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
        versions = {m.group('version_name') for _, m in candidates}
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

        # Пересборка версии заменяет прежний релиз, сохраняя дефолтность.
        existing = Release.objects.filter(version_name=version_name).first()
        was_default = bool(existing and existing.is_default)
        if existing:
            existing.apk.delete(save=False)
            existing.delete()

        release = Release.create_from_apk(
            apk_path, version_name,
            set_default=opts['set_default'] or was_default,
        )

        verb = 'Заменён' if existing else 'Зарегистрирован'
        self.stdout.write(self.style.SUCCESS(
            f'{verb} релиз {release} '
            f'(default={release.is_default}) → {release.download_url}'
        ))

        if opts['cleanup']:
            os.remove(apk_path)
            self.stdout.write(f'Удалён из incoming: {name}')
