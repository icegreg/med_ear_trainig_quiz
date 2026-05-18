"""Тесты EP клиентских логов пациента."""
import json
import shutil
import tempfile
from pathlib import Path

from django.test import override_settings

from core import client_logs
from .helpers import APITestBase


class ClientLogsTest(APITestBase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls._logs_dir = Path(tempfile.mkdtemp(prefix='test_client_logs_'))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls._logs_dir, ignore_errors=True)
        super().tearDownClass()

    def setUp(self):
        # Чистим файл лога этого пациента между тестами
        path = self._logs_dir / f'patient_{self.patient.pk}.jsonl'
        if path.exists():
            path.unlink()

    def _post(self, entries):
        return self.client.post(
            '/api/patients/logs',
            data=json.dumps({'entries': entries}),
            content_type='application/json',
            **self.patient_headers(),
        )

    @override_settings()  # ensure decorator stacking
    def test_logs_dropped_when_disabled(self):
        with override_settings(CLIENT_LOGS_DIR=self._logs_dir):
            self.patient.logging_enabled = False
            self.patient.doctor.logging_enabled = False
            self.patient.save(update_fields=['logging_enabled'])
            self.patient.doctor.save(update_fields=['logging_enabled'])

            resp = self._post([{
                'client_ts': '2026-05-18T12:00:00Z',
                'method': 'GET',
                'path': '/api/patients/me',
                'status_code': 200,
            }])
            self.assertEqual(resp.status_code, 200)
            self.assertEqual(resp.json(), {'enabled': False, 'accepted': 0})
            self.assertEqual(client_logs.line_count(self.patient.pk), 0)

    def test_logs_written_when_patient_enabled(self):
        with override_settings(CLIENT_LOGS_DIR=self._logs_dir):
            self.patient.logging_enabled = True
            self.patient.save(update_fields=['logging_enabled'])

            resp = self._post([
                {'client_ts': '2026-05-18T12:00:00Z', 'method': 'GET',
                 'path': '/api/patients/me', 'status_code': 200},
                {'client_ts': '2026-05-18T12:00:01Z', 'method': 'GET',
                 'path': '/api/quizzes/1', 'status_code': 404,
                 'error_message': 'Not Found'},
            ])
            self.assertEqual(resp.status_code, 200)
            self.assertEqual(resp.json(), {'enabled': True, 'accepted': 2})
            self.assertEqual(client_logs.line_count(self.patient.pk), 2)

            lines = client_logs.read_tail(self.patient.pk)
            parsed = [json.loads(ln) for ln in lines]
            self.assertEqual(parsed[0]['method'], 'GET')
            self.assertEqual(parsed[1]['status_code'], 404)
            # Сервер добавляет server_received_at
            self.assertIn('server_received_at', parsed[0])

    def test_doctor_flag_enables_all_his_patients(self):
        with override_settings(CLIENT_LOGS_DIR=self._logs_dir):
            self.patient.logging_enabled = False
            self.patient.save(update_fields=['logging_enabled'])
            self.patient.doctor.logging_enabled = True
            self.patient.doctor.save(update_fields=['logging_enabled'])

            resp = self._post([{'client_ts': 'x', 'method': 'GET', 'path': '/p',
                                'status_code': 200}])
            self.assertEqual(resp.json()['enabled'], True)
            self.assertEqual(client_logs.line_count(self.patient.pk), 1)

    def test_profile_exposes_effective_logging_enabled(self):
        # Ни у пациента, ни у врача
        self.patient.logging_enabled = False
        self.patient.save(update_fields=['logging_enabled'])
        self.patient.doctor.logging_enabled = False
        self.patient.doctor.save(update_fields=['logging_enabled'])
        resp = self.client.get('/api/patients/me', **self.patient_headers())
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(resp.json()['logging_enabled'])

        # Включаем у врача — пациент должен увидеть True
        self.patient.doctor.logging_enabled = True
        self.patient.doctor.save(update_fields=['logging_enabled'])
        resp = self.client.get('/api/patients/me', **self.patient_headers())
        self.assertTrue(resp.json()['logging_enabled'])
