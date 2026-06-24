"""Smoke-тесты админки: все разделы открываются без ошибок (HTTP 200).

Регрессия: в Django 6 `format_html` эскейпит аргументы в SafeString до
вызова .format(), поэтому числовые формат-коды (`{:.1f}`) внутри шаблона
падают с ValueError. Баг проявляется только когда у пациента непустые
клиентские логи (ветка с размером в KB), поэтому фикстура их создаёт.
"""
import shutil
import tempfile
from pathlib import Path

from django.contrib import admin
from django.contrib.admin.helpers import ACTION_CHECKBOX_NAME
from django.contrib.auth.models import User
from django.test import override_settings
from django.urls import reverse

from core import client_logs
from core.models import (
    Doctor,
    Notification,
    Patient,
    PatientQuizAssignment,
    QuizResult,
)

from .helpers import APITestBase


class AdminSectionsTest(APITestBase):
    """Проверяет, что каждый раздел админки рендерится без ошибок."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls._logs_dir = Path(tempfile.mkdtemp(prefix='test_admin_logs_'))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls._logs_dir, ignore_errors=True)
        super().tearDownClass()

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()

        # Суперпользователь для входа в админку
        cls.admin_user = User.objects.create_superuser(
            username='admin', password='adminpass123', email='admin@test.com',
        )

        # Результат теста (для раздела QuizResult)
        cls.assignment.status = PatientQuizAssignment.Status.COMPLETED
        cls.assignment.save(update_fields=['status'])
        cls.result = QuizResult.objects.create(
            assignment=cls.assignment,
            answers=[{'question_id': cls.question.pk, 'answer': 'B'}],
            score=1,
        )

        # Уведомление (для раздела Notification)
        cls.notification = Notification.objects.create(
            doctor=cls.doctor,
            type=Notification.Type.QUIZ_COMPLETED,
            message='Пациент прошёл тест',
        )

    def setUp(self):
        self.client.force_login(self.admin_user)

    def _core_modeladmins(self):
        """Все зарегистрированные ModelAdmin приложения core."""
        return [
            (model, model_admin)
            for model, model_admin in admin.site._registry.items()
            if model._meta.app_label == 'core'
        ]

    def test_admin_index_opens(self):
        resp = self.client.get(reverse('admin:index'))
        self.assertEqual(resp.status_code, 200)

    def test_all_changelists_open(self):
        """Список объектов каждого раздела отдаёт 200 (с данными в БД)."""
        with override_settings(CLIENT_LOGS_DIR=self._logs_dir):
            # Непустые логи пациента — чтобы сработала ветка с размером KB
            client_logs.append_entries(
                self.patient.pk,
                [{'level': 'INFO', 'msg': 'x' * 2048}],
            )
            for model, _ in self._core_modeladmins():
                url = reverse(
                    f'admin:{model._meta.app_label}_{model._meta.model_name}_changelist'
                )
                resp = self.client.get(url)
                self.assertEqual(
                    resp.status_code, 200,
                    msg=f'changelist {model._meta.model_name} -> {resp.status_code}',
                )

    def test_all_change_views_open(self):
        """Страница объекта каждого раздела отдаёт 200 (с данными в БД)."""
        with override_settings(CLIENT_LOGS_DIR=self._logs_dir):
            client_logs.append_entries(
                self.patient.pk,
                [{'level': 'INFO', 'msg': 'y' * 2048}],
            )
            for model, _ in self._core_modeladmins():
                obj = model._default_manager.first()
                if obj is None:
                    continue
                url = reverse(
                    f'admin:{model._meta.app_label}_{model._meta.model_name}_change',
                    args=[obj.pk],
                )
                resp = self.client.get(url)
                self.assertEqual(
                    resp.status_code, 200,
                    msg=f'change {model._meta.model_name} -> {resp.status_code}',
                )

    def test_patient_changelist_with_empty_logs(self):
        """Список пациентов открывается и когда логи пустые (ветка «пусто»)."""
        with override_settings(CLIENT_LOGS_DIR=self._logs_dir):
            # Гарантируем отсутствие файла логов
            path = client_logs.log_path(self.patient.pk)
            if path.exists():
                path.unlink()
            url = reverse('admin:core_patient_changelist')
            resp = self.client.get(url)
            self.assertEqual(resp.status_code, 200)


class ReassignPatientActionTest(APITestBase):
    """Массовое переназначение пациентов другому врачу через admin action."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.admin_user = User.objects.create_superuser(
            username='admin', password='adminpass123', email='admin@test.com',
        )
        # Ещё пара пациентов у doctor1, чтобы переназначать массово
        cls.patient_b = Patient.objects.create(
            user=User.objects.create_user(username='patientB', password='p'),
            doctor=cls.doctor,
        )
        cls.patient_c = Patient.objects.create(
            user=User.objects.create_user(username='patientC', password='p'),
            doctor=cls.doctor,
        )
        # Пациент без врача (doctor = null)
        cls.patient_orphan = Patient.objects.create(
            user=User.objects.create_user(username='orphan', password='p'),
            doctor=None,
        )
        cls.changelist_url = reverse('admin:core_patient_changelist')

    def setUp(self):
        self.client.force_login(self.admin_user)

    def _action_post(self, pks, apply=False, doctor=None):
        data = {
            'action': 'reassign_to_doctor',
            ACTION_CHECKBOX_NAME: [str(pk) for pk in pks],
        }
        if apply:
            data['apply'] = '1'
            if doctor is not None:
                data['doctor'] = str(doctor.id)
        return self.client.post(self.changelist_url, data, follow=True)

    def test_intermediate_page_renders(self):
        """Без apply показывается промежуточная страница выбора врача."""
        resp = self._action_post([self.patient.pk, self.patient_b.pk])
        self.assertEqual(resp.status_code, 200)
        self.assertContains(resp, 'Переназначить пациентов')
        self.assertContains(resp, 'name="doctor"')
        # Скрытые поля с pk выбранных пациентов
        self.assertContains(resp, f'value="{self.patient.pk}"')

    def test_bulk_reassign_changes_doctor(self):
        """apply переназначает всех выбранных пациентов целевому врачу."""
        resp = self._action_post(
            [self.patient.pk, self.patient_b.pk, self.patient_c.pk],
            apply=True, doctor=self.doctor2,
        )
        self.assertEqual(resp.status_code, 200)
        for p in (self.patient, self.patient_b, self.patient_c):
            p.refresh_from_db()
            self.assertEqual(p.doctor, self.doctor2)

    def test_reassign_creates_notification_for_source_doctor(self):
        """Прежний врач каждого пациента получает уведомление о передаче."""
        before = Notification.objects.filter(doctor=self.doctor).count()
        self._action_post(
            [self.patient.pk, self.patient_b.pk],
            apply=True, doctor=self.doctor2,
        )
        notes = Notification.objects.filter(
            doctor=self.doctor,
            type=Notification.Type.PATIENT_TRANSFERRED,
        )
        self.assertEqual(notes.count() - before, 2)
        note = notes.latest('created_at')
        self.assertEqual(note.data['to_doctor_id'], str(self.doctor2.id))
        self.assertEqual(note.data['via'], 'admin')

    def test_skip_patient_already_at_target(self):
        """Пациент, уже закреплённый за целевым врачом, пропускается."""
        self.patient_b.doctor = self.doctor2
        self.patient_b.save(update_fields=['doctor'])
        before = Notification.objects.count()
        self._action_post(
            [self.patient.pk, self.patient_b.pk],
            apply=True, doctor=self.doctor2,
        )
        # patient переназначен (+1 уведомление), patient_b пропущен (0)
        self.assertEqual(Notification.objects.count() - before, 1)

    def test_reassign_orphan_patient_no_notification(self):
        """Пациент без врача переназначается без падения и без уведомления."""
        before = Notification.objects.count()
        self._action_post(
            [self.patient_orphan.pk], apply=True, doctor=self.doctor2,
        )
        self.patient_orphan.refresh_from_db()
        self.assertEqual(self.patient_orphan.doctor, self.doctor2)
        self.assertEqual(Notification.objects.count(), before)

    def test_apply_without_doctor_keeps_assignment(self):
        """Без выбранного врача переназначение не выполняется (форма невалидна)."""
        resp = self._action_post(
            [self.patient.pk], apply=True, doctor=None,
        )
        self.assertEqual(resp.status_code, 200)
        self.patient.refresh_from_db()
        self.assertEqual(self.patient.doctor, self.doctor)
