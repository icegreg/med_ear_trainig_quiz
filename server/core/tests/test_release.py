"""Тесты реестра релизов APK: модель, публичная раздача, публичный API."""
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


def make_release(version_name='0.6.0', version_code=1, is_default=False):
    return Release.objects.create(
        version_name=version_name,
        version_code=version_code,
        is_default=is_default,
        file_size=len(b'APKDATA'),
        apk=SimpleUploadedFile(
            f'tnoise-{version_name}+{version_code}.apk', b'APKDATA'
        ),
    )


@override_settings(MEDIA_ROOT=_MEDIA)
class ReleaseModelTest(TestCase):
    def test_str(self):
        self.assertEqual(str(make_release('0.6.0', 2)), '0.6.0+2')

    def test_download_url(self):
        rel = make_release('0.6.0', 2)
        self.assertTrue(rel.download_url.startswith('/releases/'))
        self.assertTrue(rel.download_url.endswith('.apk'))

    def test_set_default_switches_default(self):
        first = make_release('0.6.0', 1, is_default=True)
        second = make_release('0.7.0', 2)

        second.set_default()

        first.refresh_from_db()
        second.refresh_from_db()
        self.assertFalse(first.is_default)
        self.assertTrue(second.is_default)
        self.assertEqual(Release.objects.filter(is_default=True).count(), 1)

    def test_set_default_idempotent(self):
        rel = make_release('0.6.0', 1, is_default=True)
        rel.set_default()
        rel.refresh_from_db()
        self.assertTrue(rel.is_default)
        self.assertEqual(Release.objects.filter(is_default=True).count(), 1)

    def test_set_default_copies_latest_apk(self):
        rel = make_release('0.6.0', 3)
        rel.set_default()
        latest = os.path.join(_MEDIA, 'releases', Release.LATEST_APK_NAME)
        self.assertTrue(os.path.isfile(latest))
        with open(latest, 'rb') as fh:
            self.assertEqual(fh.read(), b'APKDATA')

    def test_only_one_default_enforced_by_db(self):
        make_release('0.6.0', 1, is_default=True)
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                make_release('0.7.0', 2, is_default=True)

    def test_version_unique(self):
        make_release('0.6.0', 1)
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                make_release('0.6.0', 1)


@override_settings(MEDIA_ROOT=_MEDIA)
class ReleasePublicServingTest(TestCase):
    """Скачивание APK доступно БЕЗ авторизации (by design, Kaiten #67040240)."""

    def test_download_public_no_auth(self):
        rel = make_release('0.6.0', 10)
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
        make_release('0.6.0', 20)
        resp = self.client.get('/api/releases/')
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.json()), 1)

    def test_latest_returns_default(self):
        make_release('0.6.0', 21)
        newest_default = make_release('0.7.0', 22)
        newest_default.set_default()

        resp = self.client.get('/api/releases/latest')
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertEqual(body['version_name'], '0.7.0')
        self.assertTrue(body['is_default'])
        self.assertEqual(body['download_url'], newest_default.download_url)

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
        # Версии у тестов разные: MEDIA_ROOT общий на модуль, и при совпадении
        # имени Django допишет к файлу случайный суффикс.
        call_command(
            'register_release', apk=self._build_apk(),
            version_name='0.10.0', version_code=7, stdout=io.StringIO(),
        )
        release = Release.objects.get()
        # Имя в хранилище не зависит от имени собранного файла: flavor в него
        # не входит (реестр привязан к стенду), '+' заменён на '-'.
        self.assertEqual(
            os.path.basename(release.apk.name), 'tnoise-0.10.0-7.apk'
        )
        self.assertIn('tnoise-0.10.0-7.apk', release.download_url)

    def test_rejects_duplicate_version(self):
        args = dict(version_name='0.11.0', version_code=8, stdout=io.StringIO())
        call_command('register_release', apk=self._build_apk(), **args)
        with self.assertRaises(CommandError):
            call_command('register_release', apk=self._build_apk(), **args)

    def test_rejects_missing_apk(self):
        with self.assertRaises(CommandError):
            call_command(
                'register_release', apk='/nope/absent.apk',
                version_name='0.10.0', version_code=7, stdout=io.StringIO(),
            )


@override_settings(MEDIA_ROOT=_MEDIA)
class RegisterIncomingCommandTest(TestCase):
    """register_incoming выводит версию из имени файла в incoming/ и идемпотентен."""

    def setUp(self):
        self.incoming = os.path.join(_MEDIA, 'releases', 'incoming')
        os.makedirs(self.incoming, exist_ok=True)
        for f in os.listdir(self.incoming):
            os.remove(os.path.join(self.incoming, f))

    def _incoming(self, name):
        with open(os.path.join(self.incoming, name), 'wb') as fh:
            fh.write(b'APKDATA')

    def _run(self, **opts):
        call_command('register_incoming', stdout=io.StringIO(), **opts)

    def test_registers_and_parses_version_from_filename(self):
        self._incoming('tnoise-preprod-release-0.12.0+9.apk')
        self._run()
        rel = Release.objects.get()
        self.assertEqual(rel.version_name, '0.12.0')
        self.assertEqual(rel.version_code, 9)
        # В хранилище — каноническое имя, а не имя из incoming.
        self.assertEqual(os.path.basename(rel.apk.name), 'tnoise-0.12.0-9.apk')

    def test_idempotent_skips_duplicate(self):
        self._incoming('tnoise-preprod-release-0.12.1+10.apk')
        self._run()
        # Повторный прогон той же версии не падает и не дублирует.
        self._run()
        self.assertEqual(Release.objects.count(), 1)

    def test_flavor_filter_picks_matching(self):
        self._incoming('tnoise-preprod-release-0.13.0+11.apk')
        self._incoming('tnoise-prod-release-0.14.0+12.apk')
        self._run(flavor='prod')
        rel = Release.objects.get()
        self.assertEqual(rel.version_name, '0.14.0')

    def test_ambiguous_without_flavor_fails(self):
        self._incoming('tnoise-preprod-release-0.13.0+11.apk')
        self._incoming('tnoise-prod-release-0.14.0+12.apk')
        with self.assertRaises(CommandError):
            self._run()
        self.assertEqual(Release.objects.count(), 0)

    def test_no_candidates_fails(self):
        with self.assertRaises(CommandError):
            self._run()

    def test_cleanup_removes_incoming_file(self):
        name = 'tnoise-preprod-release-0.15.0+13.apk'
        self._incoming(name)
        self._run(cleanup=True)
        self.assertFalse(os.path.isfile(os.path.join(self.incoming, name)))

    def test_set_default(self):
        self._incoming('tnoise-preprod-release-0.16.0+14.apk')
        self._run(set_default=True)
        self.assertTrue(Release.objects.get().is_default)
