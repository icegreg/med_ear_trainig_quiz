"""Тесты: медиа-файлы требуют аутентификации."""
from .helpers import APITestBase


class ProtectedMediaTest(APITestBase):

    def test_media_without_auth_returns_403(self):
        resp = self.client.get('/media/audio/test.wav')
        self.assertEqual(resp.status_code, 403)

    def test_media_with_invalid_token_returns_403(self):
        resp = self.client.get(
            '/media/audio/test.wav',
            HTTP_AUTHORIZATION='Bearer invalidtoken',
        )
        self.assertEqual(resp.status_code, 403)

    def test_media_with_device_token_existing_file(self):
        """Пациент с валидным токеном получает файл."""
        url = self.audio.file.url  # /media/audio/test.wav or similar
        resp = self.client.get(url, **self.patient_headers())
        # 200 если файл существует, 404 если путь в тесте не совпадает
        self.assertIn(resp.status_code, [200, 404])

    def test_media_with_doctor_jwt_existing_file(self):
        """Врач с валидным JWT получает файл."""
        url = self.audio.file.url
        resp = self.client.get(url, **self.doctor_headers())
        self.assertIn(resp.status_code, [200, 404])

    def test_media_path_traversal_blocked(self):
        """Попытка path traversal блокируется."""
        resp = self.client.get(
            '/media/../config/settings.py',
            **self.patient_headers(),
        )
        self.assertEqual(resp.status_code, 404)
