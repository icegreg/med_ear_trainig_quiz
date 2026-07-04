"""Тесты генерации логина, suggest-login и сброса пароля пациента."""
import json
from datetime import date

from django.contrib.auth.models import User

from core.models import Patient
from core.utils import build_login_base, generate_patient_login

from .helpers import APITestBase


class LoginBaseTest(APITestBase):
    """Формат базового логина: транслит фамилии + инициалы."""

    def test_full_fio(self):
        self.assertEqual(
            build_login_base('Иванов', 'Пётр', 'Сергеевич'), 'ivanovps'
        )

    def test_no_patronymic(self):
        self.assertEqual(build_login_base('Иванова', 'Анна', ''), 'ivanovaa')

    def test_only_last_name(self):
        self.assertEqual(build_login_base('Сидоров', '', ''), 'sidorov')

    def test_complex_letters(self):
        # Щукин Юрий Яковлевич → shchukin + yu + ya
        self.assertEqual(
            build_login_base('Щукин', 'Юрий', 'Яковлевич'), 'shchukinyuya'
        )

    def test_empty_fallback(self):
        self.assertEqual(build_login_base('', '', ''), 'patient')

    def test_latin_input_kept(self):
        self.assertEqual(build_login_base('Smith', 'John', ''), 'smithj')


class GenerateLoginSuffixTest(APITestBase):
    """Подбор свободного логина: год рождения → инкремент."""

    def test_free_base_returned_as_is(self):
        login = generate_patient_login('Козлов', 'Иван', 'Петрович')
        self.assertEqual(login, 'kozlovip')

    def test_birth_year_suffix_when_taken(self):
        User.objects.create_user(username='ivanovps', password='x')
        login = generate_patient_login(
            'Иванов', 'Пётр', 'Сергеевич', birth_date=date(1990, 5, 1)
        )
        self.assertEqual(login, 'ivanovps90')

    def test_increment_when_base_and_year_taken(self):
        User.objects.create_user(username='ivanovps', password='x')
        User.objects.create_user(username='ivanovps90', password='x')
        login = generate_patient_login(
            'Иванов', 'Пётр', 'Сергеевич', birth_date=date(1990, 5, 1)
        )
        self.assertEqual(login, 'ivanovps2')

    def test_increment_when_no_birth_date(self):
        User.objects.create_user(username='ivanovps', password='x')
        login = generate_patient_login('Иванов', 'Пётр', 'Сергеевич')
        self.assertEqual(login, 'ivanovps2')

    def test_increment_skips_taken_numbers(self):
        User.objects.create_user(username='ivanovps', password='x')
        User.objects.create_user(username='ivanovps2', password='x')
        User.objects.create_user(username='ivanovps3', password='x')
        login = generate_patient_login('Иванов', 'Пётр', 'Сергеевич')
        self.assertEqual(login, 'ivanovps4')


class SuggestLoginEndpointTest(APITestBase):

    def test_suggest_login_success(self):
        resp = self.client.post(
            '/api/doctors/patients/suggest-login',
            data=json.dumps({
                'last_name': 'Иванов',
                'first_name': 'Пётр',
                'patronymic': 'Сергеевич',
            }),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()['login'], 'ivanovps')

    def test_suggest_login_uses_birth_year_on_collision(self):
        User.objects.create_user(username='ivanovps', password='x')
        resp = self.client.post(
            '/api/doctors/patients/suggest-login',
            data=json.dumps({
                'last_name': 'Иванов',
                'first_name': 'Пётр',
                'patronymic': 'Сергеевич',
                'birth_date': '1988-01-01',
            }),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()['login'], 'ivanovps88')

    def test_suggest_login_requires_auth(self):
        resp = self.client.post(
            '/api/doctors/patients/suggest-login',
            data=json.dumps({'last_name': 'Иванов'}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)


class ResetPasswordEndpointTest(APITestBase):

    def test_reset_password_success(self):
        resp = self.client.post(
            f'/api/doctors/patients/{self.patient.id}/reset-password',
            data=json.dumps({'new_password': 'NewPass123abc'}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()['username'], 'patient1')
        self.patient_user.refresh_from_db()
        self.assertTrue(self.patient_user.check_password('NewPass123abc'))

    def test_reset_password_requires_auth(self):
        resp = self.client.post(
            f'/api/doctors/patients/{self.patient.id}/reset-password',
            data=json.dumps({'new_password': 'NewPass123abc'}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_reset_password_other_doctors_patient_404(self):
        """Врач не может сбросить пароль чужому пациенту."""
        other_user = User.objects.create_user(username='foreign', password='x')
        foreign = Patient.objects.create(user=other_user, doctor=self.doctor2)
        resp = self.client.post(
            f'/api/doctors/patients/{foreign.id}/reset-password',
            data=json.dumps({'new_password': 'NewPass123abc'}),
            content_type='application/json',
            **self.doctor_headers(),
        )
        self.assertEqual(resp.status_code, 404)
        other_user.refresh_from_db()
        self.assertFalse(other_user.check_password('NewPass123abc'))
