"""Просмотр реестра релизов и управление дефолтом из CLI (Kaiten #67702724).

  python manage.py releases list                  # список APK, дефолт помечен
  python manage.py releases set-default 0.10.1     # сделать версию дефолтной
  python manage.py releases unset-default          # снять дефолт (latest.apk → 404)

Дефолтный релиз ровно один — гарантируется unique-констрейнтом на is_default и
Release.set_default(). unset-default убирает latest.apk, чтобы стабильная ссылка
честно отдавала 404 (см. Release.refresh_latest).
"""
from django.core.management.base import BaseCommand, CommandError

from core.models import Release


class Command(BaseCommand):
    help = 'Список релизов APK и управление дефолтным (list/set-default/unset-default).'

    def add_arguments(self, parser):
        parser.add_argument(
            'action', choices=['list', 'set-default', 'unset-default'],
            help='Действие',
        )
        parser.add_argument(
            'version', nargs='?',
            help='version_name для set-default (напр. 0.10.1)',
        )

    def handle(self, *args, **opts):
        action = opts['action']
        if action == 'list':
            self._list()
        elif action == 'set-default':
            self._set_default(opts['version'])
        elif action == 'unset-default':
            self._unset_default()

    def _list(self):
        releases = list(Release.objects.all())  # ordering: -created_at
        if not releases:
            self.stdout.write('Реестр пуст.')
            return
        self.stdout.write(f'{"деф":<4}{"версия":<16}{"размер":>10}  {"собран":<20}  ссылка')
        for r in releases:
            mark = ' * ' if r.is_default else '   '
            size = f'{r.file_size / (1024 * 1024):.1f} МБ' if r.file_size else '—'
            when = r.created_at.strftime('%Y-%m-%d %H:%M')
            self.stdout.write(
                f'{mark:<4}{r.version_name:<16}{size:>10}  {when:<20}  {r.download_url}'
            )
        if not any(r.is_default for r in releases):
            self.stdout.write(self.style.WARNING(
                'Дефолт не задан — /releases/latest.apk отдаёт 404.'
            ))

    def _set_default(self, version):
        if not version:
            raise CommandError('Укажите версию: releases set-default <version_name>')
        release = Release.objects.filter(version_name=version).first()
        if release is None:
            raise CommandError(f'Релиз {version} не найден.')
        release.set_default()
        self.stdout.write(self.style.SUCCESS(
            f'Дефолтным сделан {release} → /releases/latest.apk = {release.download_url}'
        ))

    def _unset_default(self):
        updated = Release.objects.filter(is_default=True).update(is_default=False)
        # Bulk update не шлёт сигналов — синхронизируем latest.apk вручную.
        Release.refresh_latest()
        if updated:
            self.stdout.write(self.style.SUCCESS(
                'Дефолт снят. /releases/latest.apk теперь отдаёт 404.'
            ))
        else:
            self.stdout.write('Дефолт и так не был задан.')
