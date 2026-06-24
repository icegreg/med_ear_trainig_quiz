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
from django.contrib.auth.models import User
from django.test import override_settings
from django.urls import reverse

from core import client_logs
from core.models import Notification, PatientQuizAssignment, QuizResult

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
