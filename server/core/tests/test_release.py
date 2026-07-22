"""Тесты реестра релизов APK: модель, публичная раздача, публичный API, команды.

Реестр хранит одну запись на версию (`version_name`); versionCode/commit/notes/
file_size из модели убраны (Kaiten #67689761). Размер — property из файла.
"""
import io
import os
import tempfile

from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db import IntegrityError, transaction
from django.test import TestCase, override_settings

from core.models import Release

_MEDIA = tempfile.mkdtemp(prefix='test_releases_')


def make_release(version_name='0.6.0', is_default=False):
    return Release.objects.create(
        version_name=version_name,
        is_default=is_default,
        apk=SimpleUploadedFile(f'tnoise-{version_name}.apk', b'APKDATA'),
    )


@override_settings(MEDIA_ROOT=_MEDIA)
class ReleaseModelTest(TestCase):
    def test_str(self):
        self.assertEqual(str(make_release('0.6.0')), '0.6.0')

    def test_file_size_from_file(self):
        # file_size — property, выводится из файла, не хранимое поле.
        self.assertEqual(make_release('0.6.0').file_size, len(b'APKDATA'))

    def test_download_url(self):
        rel = make_release('0.6.0')
        self.assertTrue(rel.download_url.startswith('/releases/'))
        self.assertTrue(rel.download_url.endswith('.apk'))

    def test_set_default_switches_default(self):
        first = make_release('0.6.0', is_default=True)
        second = make_release('0.7.0')

        second.set_default()

        first.refresh_from_db()
        second.refresh_from_db()
        self.assertFalse(first.is_default)
        self.assertTrue(second.is_default)
        self.assertEqual(Release.objects.filter(is_default=True).count(), 1)

    def test_set_default_idempotent(self):
        rel = make_release('0.6.0', is_default=True)
        rel.set_default()
        rel.refresh_from_db()
        self.assertTrue(rel.is_default)
        self.assertEqual(Release.objects.filter(is_default=True).count(), 1)

    def test_set_default_copies_latest_apk(self):
        rel = make_release('0.6.0')
        rel.set_default()
        latest = os.path.join(_MEDIA, 'releases', Release.LATEST_APK_NAME)
        self.assertTrue(os.path.isfile(latest))
        with open(latest, 'rb') as fh:
            self.assertEqual(fh.read(), b'APKDATA')

    def test_only_one_default_enforced_by_db(self):
        make_release('0.6.0', is_default=True)
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                make_release('0.7.0', is_default=True)

    def test_version_unique(self):
        make_release('0.6.0')
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                make_release('0.6.0')


@override_settings(MEDIA_ROOT=_MEDIA)
class ReleasePublicServingTest(TestCase):
    """Скачивание APK доступно БЕЗ авторизации (by design, Kaiten #67040240)."""

    def test_download_public_no_auth(self):
        rel = make_release('0.6.1')
        resp = self.client.get(rel.download_url)
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(b''.join(resp.streaming_content), b'APKDATA')

    def test_download_missing_returns_404(self):
        resp = self.client.get('/releases/nope.apk')
        self.assertEqual(resp.status_code, 404)


@override_settings(MEDIA_ROOT=_MEDIA)
class ReleaseApiTest(TestCase):
    """Публичный API реестра — без токена."""

    def test_list_public(self):
        make_release('0.6.2')
        resp = self.client.get('/api/releases/')
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.json()), 1)

    def test_latest_returns_default(self):
        make_release('0.6.3')
        newest_default = make_release('0.7.3')
        newest_default.set_default()

        resp = self.client.get('/api/releases/latest')
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertEqual(body['version_name'], '0.7.3')
        self.assertTrue(body['is_default'])
        self.assertEqual(body['download_url'], newest_default.download_url)
        # Удалённых полей в контракте больше нет.
        for gone in ('version_code', 'commit_sha', 'notes'):
            self.assertNotIn(gone, body)

    def test_latest_empty_returns_404(self):
        resp = self.client.get('/api/releases/latest')
        self.assertEqual(resp.status_code, 404)


@override_settings(MEDIA_ROOT=_MEDIA)
class RegisterReleaseCommandTest(TestCase):
    """register_release задаёт имя, под которым APK скачивает пользователь."""

    def _build_apk(self, name='tnoise-prod-release-0.10.0+7.apk'):
        """Кладёт фейковый APK во временный файл, как это делает сборка."""
        path = os.path.join(tempfile.mkdtemp(prefix='test_apk_'), name)
        with open(path, 'wb') as fh:
            fh.write(b'APKDATA')
        return path

    def test_stored_filename_is_branded(self):
        call_command(
            'register_release', apk=self._build_apk(),
            version_name='0.10.0', stdout=io.StringIO(),
        )
        release = Release.objects.get()
        # Имя в хранилище: только версия, без flavor и versionCode.
        self.assertEqual(os.path.basename(release.apk.name), 'tnoise-0.10.0.apk')
        self.assertIn('tnoise-0.10.0.apk', release.download_url)

    def test_rejects_duplicate_version(self):
        args = dict(version_name='0.11.0', stdout=io.StringIO())
        call_command('register_release', apk=self._build_apk(), **args)
        with self.assertRaises(CommandError):
            call_command('register_release', apk=self._build_apk(), **args)

    def test_rejects_missing_apk(self):
        with self.assertRaises(CommandError):
            call_command(
                'register_release', apk='/nope/absent.apk',
                version_name='0.10.0', stdout=io.StringIO(),
            )

    def test_legacy_args_accepted_and_ignored(self):
        # Деплой стендов ещё передаёт --version-code/--commit/--notes.
        call_command(
            'register_release', apk=self._build_apk(),
            version_name='0.12.0', version_code='9', commit='abc123',
            notes='старое', stdout=io.StringIO(),
        )
        self.assertTrue(Release.objects.filter(version_name='0.12.0').exists())


@override_settings(MEDIA_ROOT=_MEDIA)
class RegisterIncomingCommandTest(TestCase):
    """register_incoming выводит версию из имени файла; пересборка заменяет релиз."""

    def setUp(self):
        self.incoming = os.path.join(_MEDIA, 'releases', 'incoming')
        os.makedirs(self.incoming, exist_ok=True)
        for f in os.listdir(self.incoming):
            os.remove(os.path.join(self.incoming, f))

    def _incoming(self, name, data=b'APKDATA'):
        with open(os.path.join(self.incoming, name), 'wb') as fh:
            fh.write(data)

    def _run(self, **opts):
        call_command('register_incoming', stdout=io.StringIO(), **opts)

    def test_registers_and_parses_version_from_filename(self):
        self._incoming('tnoise-preprod-release-0.12.0+9.apk')
        self._run()
        rel = Release.objects.get()
        self.assertEqual(rel.version_name, '0.12.0')
        # В хранилище — только версия, без flavor и versionCode.
        self.assertEqual(os.path.basename(rel.apk.name), 'tnoise-0.12.0.apk')

    def test_rebuild_replaces_same_version(self):
        self._incoming('tnoise-preprod-release-0.12.1+10.apk', b'FIRST')
        self._run(cleanup=True)
        # Пересборка той же версии (другой код/содержимое) — заменяет запись.
        self._incoming('tnoise-preprod-release-0.12.1+11.apk', b'SECOND')
        self._run(cleanup=True)
        self.assertEqual(Release.objects.filter(version_name='0.12.1').count(), 1)
        rel = Release.objects.get(version_name='0.12.1')
        with rel.apk.open('rb') as fh:
            self.assertEqual(fh.read(), b'SECOND')

    def test_replace_preserves_default(self):
        self._incoming('tnoise-preprod-release-0.13.0+1.apk')
        self._run(set_default=True)
        self.assertTrue(Release.objects.get(version_name='0.13.0').is_default)
        # Пересборка без --set-default сохраняет статус дефолтного.
        self._incoming('tnoise-preprod-release-0.13.0+2.apk')
        self._run()
        self.assertTrue(Release.objects.get(version_name='0.13.0').is_default)

    def test_flavor_filter_picks_matching(self):
        self._incoming('tnoise-preprod-release-0.14.0+1.apk')
        self._incoming('tnoise-prod-release-0.15.0+1.apk')
        self._run(flavor='prod')
        rel = Release.objects.get()
        self.assertEqual(rel.version_name, '0.15.0')

    def test_ambiguous_without_flavor_fails(self):
        self._incoming('tnoise-preprod-release-0.14.0+1.apk')
        self._incoming('tnoise-prod-release-0.15.0+1.apk')
        with self.assertRaises(CommandError):
            self._run()
        self.assertEqual(Release.objects.count(), 0)

    def test_no_candidates_fails(self):
        with self.assertRaises(CommandError):
            self._run()

    def test_cleanup_removes_incoming_file(self):
        name = 'tnoise-preprod-release-0.16.0+1.apk'
        self._incoming(name)
        self._run(cleanup=True)
        self.assertFalse(os.path.isfile(os.path.join(self.incoming, name)))


@override_settings(MEDIA_ROOT=_MEDIA)
class LatestApkSyncTest(TestCase):
    """latest.apk всегда отражает дефолт; без дефолта ссылка 404 (Kaiten #67702702)."""

    def _latest_path(self):
        return os.path.join(_MEDIA, 'releases', Release.LATEST_APK_NAME)

    def test_default_creates_latest(self):
        make_release('1.0', is_default=True)
        self.assertTrue(os.path.isfile(self._latest_path()))
        self.assertEqual(self.client.get('/releases/latest.apk').status_code, 200)

    def test_uncheck_default_removes_latest(self):
        rel = make_release('1.1', is_default=True)
        self.assertTrue(os.path.isfile(self._latest_path()))
        # Снятие галочки в админке — обычный save().
        rel.is_default = False
        rel.save()
        self.assertFalse(os.path.isfile(self._latest_path()))
        self.assertEqual(self.client.get('/releases/latest.apk').status_code, 404)

    def test_delete_default_removes_latest(self):
        rel = make_release('1.2', is_default=True)
        self.assertTrue(os.path.isfile(self._latest_path()))
        rel.delete()
        self.assertFalse(os.path.isfile(self._latest_path()))
        self.assertEqual(self.client.get('/releases/latest.apk').status_code, 404)

    def test_switch_default_repoints_latest(self):
        make_release('1.3', is_default=True)
        newer = make_release('1.4')
        newer.set_default()
        with open(self._latest_path(), 'rb') as fh:
            self.assertEqual(fh.read(), b'APKDATA')
        self.assertEqual(Release.objects.filter(is_default=True).count(), 1)


@override_settings(MEDIA_ROOT=_MEDIA)
class ReleasesCommandTest(TestCase):
    """CLI releases: list / set-default / unset-default (Kaiten #67702724)."""

    def _latest_path(self):
        return os.path.join(_MEDIA, 'releases', Release.LATEST_APK_NAME)

    def _run(self, *args):
        out = io.StringIO()
        call_command('releases', *args, stdout=out)
        return out.getvalue()

    def test_list_shows_releases(self):
        make_release('0.9')
        make_release('1.0', is_default=True)
        out = self._run('list')
        self.assertIn('0.9', out)
        self.assertIn('1.0', out)

    def test_set_default_switches(self):
        make_release('0.9', is_default=True)
        make_release('1.0')
        self._run('set-default', '1.0')
        self.assertTrue(Release.objects.get(version_name='1.0').is_default)
        self.assertFalse(Release.objects.get(version_name='0.9').is_default)
        self.assertEqual(Release.objects.filter(is_default=True).count(), 1)

    def test_set_default_nonexistent_fails(self):
        with self.assertRaises(CommandError):
            self._run('set-default', 'нет-такой')

    def test_unset_default_removes_latest(self):
        make_release('1.0', is_default=True)
        self.assertTrue(os.path.isfile(self._latest_path()))
        self._run('unset-default')
        self.assertFalse(Release.objects.filter(is_default=True).exists())
        self.assertFalse(os.path.isfile(self._latest_path()))
        self.assertEqual(self.client.get('/releases/latest.apk').status_code, 404)
