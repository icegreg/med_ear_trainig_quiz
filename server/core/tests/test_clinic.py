"""Тесты сущности «Клиника»: модель, миграция, API, логин с префиксом, админка."""
import json

from django.contrib.admin.helpers import ACTION_CHECKBOX_NAME
from django.contrib.auth.models import User
from django.urls import reverse

from core.models import Clinic, Patient
from core.utils import build_login_base, generate_patient_login

from .helpers import APITestBase


class ClinicModelTest(APITestBase):
    """Модель клиники и дефолтная клиника из миграции."""

    def test_str(self):
        clinic = Clinic.objects.create(name='ЛОР-центр', abbreviation='LOR')
        self.assertEqual(str(clinic), 'ЛОР-центр (LOR)')

    def test_default_clinic_exists_after_migration(self):
        """Миграция 0014 создаёт дефолтную клинику CLN."""
        self.assertTrue(Clinic.objects.filter(abbreviation='CLN').exists())

    def test_abbreviation_unique(self):
        Clinic.objects.create(name='Первая', abbreviation='ABC')
        with self.assertRaises(Exception):
            Clinic.objects.create(name='Вторая', abbreviation='ABC')


class ClinicLoginFormatTest(APITestBase):
    """Формат логина с префиксом аббревиатуры клиники."""

    def test_base_with_clinic_prefix(self):
        self.assertEqual(
            build_login_base('Иванов', 'Пётр', 'Сергеевич', 'MSK'),
            'msk-ivanovps',
        )

    def test_base_without_clinic_unchanged(self):
        self.assertEqual(build_login_base('Иванов', 'Пётр', 'Сергеевич'), 'ivanovps')

    def test_generate_with_clinic_free(self):
        login = generate_patient_login('Иванов', 'Пётр', 'Сергеевич', clinic_abbr='MSK')
        self.assertEqual(login, 'msk-ivanovps')

    def test_generate_with_clinic_duplicate_gets_number(self):
        User.objects.create_user(username='msk-ivanovps', password='x')
        login = generate_patient_login('Иванов', 'Пётр', 'Сергеевич', clinic_abbr='MSK')
        self.assertEqual(login, 'msk-ivanovps2')

    def test_generate_with_clinic_ignores_birth_year(self):
        """С клиникой год рождения не используется — сразу числовой суффикс."""
        from datetime import date
        User.objects.create_user(username='msk-ivanovps', password='x')
        login = generate_patient_login(
            'Иванов', 'Пётр', 'Сергеевич',
            birth_date=date(1990, 5, 1), clinic_abbr='MSK',
        )
        self.assertEqual(login, 'msk-ivanovps2')


class ListClinicsEndpointTest(APITestBase):

    def test_list_clinics_success(self):
        Clinic.objects.create(name='ЛОР-центр', abbreviation='LOR')
        resp = self.client.get('/api/doctors/clinics', **self.doctor_headers())
        self.assertEqual(resp.status_code, 200)
        abbrs = {c['abbreviation'] for c in resp.json()}
        self.assertIn('CLN', abbrs)  # дефолтная
        self.assertIn('LOR', abbrs)


class SuggestLoginWithClinicTest(APITestBase):

    def test_suggest_login_with_clinic_prefix(self):
        clinic = Clinic.objects.create(name='Москва', abbreviation='MSK')
        resp = self.client.post(
            '/api/doctors/patients/suggest-login',
            data=json.dumps({
                'last_name': 'Иванов',
                'first_name': 'Пётр',
                'patronymic': 'Сергеевич',
                'clinic_id': clinic.id,
            }),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()['login'], 'msk-ivanovps')


class CreatePatientWithClinicTest(APITestBase):

    def test_create_patient_assigns_clinic(self):
        clinic = Clinic.objects.create(name='Москва', abbreviation='MSK')
        resp = self.client.post(
            '/api/doctors/patients',
            data=json.dumps({
                'username': 'msk-testps',
                'password': 'Secret12345',
                'clinic_id': clinic.id,
                'last_name': 'Тестов',
            }),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        patient = Patient.objects.get(id=resp.json()['id'])
        self.assertEqual(patient.clinic, clinic)

    def test_create_patient_invalid_clinic_400(self):
        resp = self.client.post(
            '/api/doctors/patients',
            data=json.dumps({
                'username': 'nobody1',
                'password': 'Secret12345',
                'clinic_id': 999999,
                'last_name': 'Тестов',
            }),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 400)
        self.assertFalse(User.objects.filter(username='nobody1').exists())

    def test_create_patient_without_clinic_ok(self):
        resp = self.client.post(
            '/api/doctors/patients',
            data=json.dumps({
                'username': 'noclinic1',
                'password': 'Secret12345',
                'last_name': 'Безклиники',
            }),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        patient = Patient.objects.get(id=resp.json()['id'])
        self.assertIsNone(patient.clinic)


class TransferClinicActionTest(APITestBase):
    """Массовый перенос пациентов в клинику через admin action."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.admin_user = User.objects.create_superuser(
            username='admin', password='adminpass123', email='admin@test.com',
        )
        cls.clinic_a = Clinic.objects.create(name='Клиника A', abbreviation='AAA')
        cls.clinic_b = Clinic.objects.create(name='Клиника B', abbreviation='BBB')
        cls.patient.clinic = cls.clinic_a
        cls.patient.save(update_fields=['clinic'])
        cls.patient_b = Patient.objects.create(
            user=User.objects.create_user(username='patB', password='p'),
            doctor=cls.doctor, clinic=cls.clinic_a,
        )
        cls.changelist_url = reverse('admin:core_patient_changelist')

    def setUp(self):
        self.client.force_login(self.admin_user)

    def _action_post(self, pks, apply=False, clinic=None):
        data = {
            'action': 'transfer_to_clinic',
            ACTION_CHECKBOX_NAME: [str(pk) for pk in pks],
        }
        if apply:
            data['apply'] = '1'
            if clinic is not None:
                data['clinic'] = str(clinic.id)
        return self.client.post(self.changelist_url, data, follow=True)

    def test_intermediate_page_renders(self):
        resp = self._action_post([self.patient.pk, self.patient_b.pk])
        self.assertEqual(resp.status_code, 200)
        self.assertContains(resp, 'Перенести пациентов в клинику')
        self.assertContains(resp, 'name="clinic"')

    def test_bulk_transfer_changes_clinic(self):
        resp = self._action_post(
            [self.patient.pk, self.patient_b.pk], apply=True, clinic=self.clinic_b,
        )
        self.assertEqual(resp.status_code, 200)
        for p in (self.patient, self.patient_b):
            p.refresh_from_db()
            self.assertEqual(p.clinic, self.clinic_b)

    def test_apply_without_clinic_keeps_assignment(self):
        resp = self._action_post([self.patient.pk], apply=True, clinic=None)
        self.assertEqual(resp.status_code, 200)
        self.patient.refresh_from_db()
        self.assertEqual(self.patient.clinic, self.clinic_a)
