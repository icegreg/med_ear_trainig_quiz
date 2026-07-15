"""Тесты публичной раздачи документации (/docs/, гейт по DOCS_DIR)."""
import os
import tempfile

from django.test import RequestFactory, TestCase, override_settings

from core.views import serve_docs

_DOCS = tempfile.mkdtemp(prefix='test_docs_')
os.makedirs(os.path.join(_DOCS, 'doctor'), exist_ok=True)
with open(os.path.join(_DOCS, 'doctor', 'index.html'), 'w') as _fh:
    _fh.write('<h1>Руководство врача</h1>')
with open(os.path.join(_DOCS, 'doctor', 'style.css'), 'w') as _fh:
    _fh.write('h1 { color: teal; }')


@override_settings(DOCS_DIR=_DOCS)
class ServeDocsTest(TestCase):
    """serve_docs раздаёт файлы БЕЗ авторизации; каталог → index.html."""

    def setUp(self):
        self.factory = RequestFactory()

    def _get(self, path):
        return serve_docs(self.factory.get(f'/docs/{path}'), path)

    def test_serves_file(self):
        resp = self._get('doctor/index.html')
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp['Content-Type'], 'text/html')
        self.assertIn('Руководство врача'.encode(), b''.join(resp.streaming_content))

    def test_directory_serves_index(self):
        resp = self._get('doctor/')
        self.assertEqual(resp.status_code, 200)
        self.assertIn('Руководство врача'.encode(), b''.join(resp.streaming_content))

    def test_serves_asset_with_mime(self):
        resp = self._get('doctor/style.css')
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp['Content-Type'], 'text/css')

    def test_missing_file_returns_404(self):
        self.assertEqual(self._get('doctor/nope.html').status_code, 404)

    def test_path_traversal_blocked(self):
        # Попытка выйти за пределы DOCS_DIR не должна отдавать чужие файлы.
        self.assertEqual(self._get('../../etc/passwd').status_code, 404)
