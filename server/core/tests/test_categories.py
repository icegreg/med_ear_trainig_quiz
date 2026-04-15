"""Тесты API категорий аудио."""
import json

from core.models import AudioCategory, AudioFile
from core.tests.helpers import APITestBase


class AudioCategoryModelTest(APITestBase):
    """Тесты модели AudioCategory."""

    def test_default_category_created_on_audio_save(self):
        """Новый AudioFile без category получает 'Общая'."""
        default = AudioCategory.get_default()
        self.assertEqual(self.audio.category, default)

    def test_get_default_idempotent(self):
        cat1 = AudioCategory.get_default()
        cat2 = AudioCategory.get_default()
        self.assertEqual(cat1.id, cat2.id)

    def test_str_nested(self):
        parent = AudioCategory.objects.create(name='Родитель')
        child = AudioCategory.objects.create(name='Ребёнок', parent=parent)
        self.assertEqual(str(child), 'Родитель / Ребёнок')


class AudioCategoryAPITest(APITestBase):
    """Тесты API категорий (через doctor router)."""

    def test_list_categories(self):
        resp = self.client.get('/api/doctors/audio-library/categories', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIsInstance(data, list)
        names = [c['name'] for c in data]
        self.assertIn('Общая', names)

    def test_create_category(self):
        resp = self.client.post(
            '/api/doctors/audio-library/categories',
            data=json.dumps({'name': 'Тональные'}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()['name'], 'Тональные')

    def test_create_subcategory(self):
        parent = AudioCategory.objects.create(name='Звуки')
        resp = self.client.post(
            '/api/doctors/audio-library/categories',
            data=json.dumps({'name': 'Высокие', 'parent_id': parent.id}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()['parent_id'], parent.id)

    def test_rename_category(self):
        cat = AudioCategory.objects.create(name='Старое')
        resp = self.client.put(
            f'/api/doctors/audio-library/categories/{cat.id}',
            data=json.dumps({'name': 'Новое'}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()['name'], 'Новое')

    def test_cannot_rename_default(self):
        default = AudioCategory.get_default()
        resp = self.client.put(
            f'/api/doctors/audio-library/categories/{default.id}',
            data=json.dumps({'name': 'Другое'}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 400)

    def test_delete_category_moves_files_to_default(self):
        cat = AudioCategory.objects.create(name='Временная')
        self.audio.category = cat
        self.audio.save(update_fields=['category'])

        resp = self.client.delete(
            f'/api/doctors/audio-library/categories/{cat.id}',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.audio.refresh_from_db()
        self.assertEqual(self.audio.category, AudioCategory.get_default())

    def test_cannot_delete_default(self):
        default = AudioCategory.get_default()
        resp = self.client.delete(
            f'/api/doctors/audio-library/categories/{default.id}',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 400)

    def test_delete_reparents_subcategories(self):
        parent = AudioCategory.objects.create(name='Родитель')
        child = AudioCategory.objects.create(name='Ребёнок', parent=parent)
        grandchild = AudioCategory.objects.create(name='Внук', parent=child)

        self.client.delete(
            f'/api/doctors/audio-library/categories/{child.id}',
            **self.doctor_headers(),
        )
        grandchild.refresh_from_db()
        self.assertEqual(grandchild.parent, parent)

    def test_move_audio(self):
        cat = AudioCategory.objects.create(name='Новая')
        resp = self.client.put(
            f'/api/doctors/audio-library/{self.audio.id}/move',
            data=json.dumps({'category_id': cat.id}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.audio.refresh_from_db()
        self.assertEqual(self.audio.category, cat)

    def test_list_audio_library(self):
        resp = self.client.get('/api/doctors/audio-library', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertGreaterEqual(len(data), 1)

    def test_list_audio_filter_by_category(self):
        default = AudioCategory.get_default()
        resp = self.client.get(
            f'/api/doctors/audio-library?category_id={default.id}',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
