"""Тесты системы уведомлений."""
import json

from core.auth import create_doctor_tokens
from core.models import Notification
from core.tests.helpers import APITestBase


class NotificationTest(APITestBase):
    """Тесты уведомлений."""

    def test_transfer_creates_notification(self):
        """Передача пациента создаёт уведомление для исходного врача."""
        resp = self.client.post(
            '/api/doctors/transfer-patient',
            data=json.dumps({
                'patient_id': self.patient.id,
                'to_doctor_id': str(self.doctor2.id),
            }),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        notif = Notification.objects.filter(doctor=self.doctor).first()
        self.assertIsNotNone(notif)
        self.assertEqual(notif.type, Notification.Type.PATIENT_TRANSFERRED)
        self.assertIn(self.patient.user.username, notif.message)

    def test_list_notifications(self):
        Notification.objects.create(
            doctor=self.doctor,
            type=Notification.Type.PATIENT_TRANSFERRED,
            message='Тестовое уведомление',
        )
        resp = self.client.get('/api/doctors/notifications', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data['unread_count'], 1)
        self.assertEqual(len(data['notifications']), 1)

    def test_list_notifications_unread_only(self):
        Notification.objects.create(
            doctor=self.doctor,
            type=Notification.Type.PATIENT_TRANSFERRED,
            message='Прочитанное',
            is_read=True,
        )
        Notification.objects.create(
            doctor=self.doctor,
            type=Notification.Type.PATIENT_TRANSFERRED,
            message='Непрочитанное',
        )
        resp = self.client.get(
            '/api/doctors/notifications?unread_only=true',
            **self.doctor_headers(),
        )
        data = resp.json()
        self.assertEqual(len(data['notifications']), 1)
        self.assertEqual(data['notifications'][0]['message'], 'Непрочитанное')

    def test_mark_read(self):
        notif = Notification.objects.create(
            doctor=self.doctor,
            type=Notification.Type.PATIENT_ADDED,
            message='Тест',
        )
        resp = self.client.post(
            f'/api/doctors/notifications/{notif.id}/read',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        notif.refresh_from_db()
        self.assertTrue(notif.is_read)

    def test_cannot_read_other_doctors_notification(self):
        notif = Notification.objects.create(
            doctor=self.doctor2,
            type=Notification.Type.PATIENT_ADDED,
            message='Чужое',
        )
        resp = self.client.post(
            f'/api/doctors/notifications/{notif.id}/read',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 404)
