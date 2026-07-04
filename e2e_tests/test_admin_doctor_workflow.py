"""E2E: полный сценарий администрирования через браузер (Django admin) + API.

Проверяемый поток:
  1. Создать врача B (получатель перевода) — admin UI.
  2. Создать врача A — admin UI.
  3. Добавить врачу A двух пациентов — doctor API (в админке нет формы создания
     пациента; пациенты заводятся через приложение врача).
  4. Перевести пациентов A → B — admin action «Переназначить».
  5. Создать тест (quiz) — admin UI.
  6. Назначить тест пациенту и сбросить пароль — doctor API (именно эти действия
     пишутся в журнал врача и в лог пациента).
  7. Прочитать журнал действий врача и лог пациента — admin UI.

Запуск (нужен поднятый docker-стек):
  cd e2e_tests && pip install -r requirements.txt
  E2E_HEADLESS=1 pytest test_admin_doctor_workflow.py     # headless
  E2E_HEADLESS=0 pytest test_admin_doctor_workflow.py     # обычный Chrome
"""
import uuid

import requests
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import Select, WebDriverWait

from conftest import BASE_URL

API = f'{BASE_URL}/api'
DOC_PASS = 'DocPass123'
PAT_PASS = 'PatPass123'


# ─── API helpers ─────────────────────────────────────────────────────────

def _doctor_token(username, password):
    r = requests.post(
        f'{API}/auth/doctor/login',
        json={'username': username, 'password': password}, timeout=10,
    )
    r.raise_for_status()
    return r.json()['access']


def _auth(token):
    return {'Authorization': f'Bearer {token}'}


# ─── admin UI helpers ────────────────────────────────────────────────────

def _admin_create_doctor(driver, wait, *, username, last_name, first_name, clinic):
    driver.get(f'{BASE_URL}/admin/core/doctor/add/')
    wait.until(EC.presence_of_element_located((By.NAME, 'username')))
    driver.find_element(By.NAME, 'username').send_keys(username)
    driver.find_element(By.NAME, 'email').send_keys(f'{username}@test.local')
    driver.find_element(By.NAME, 'password').send_keys(DOC_PASS)
    driver.find_element(By.NAME, 'last_name').send_keys(last_name)
    driver.find_element(By.NAME, 'first_name').send_keys(first_name)
    driver.find_element(By.NAME, 'clinic').send_keys(clinic)
    driver.find_element(By.NAME, '_save').click()
    wait.until(EC.presence_of_element_located(
        (By.CSS_SELECTOR, 'ul.messagelist li.success')))
    assert not driver.find_elements(By.CSS_SELECTOR, '.errorlist'), \
        f'Ошибка создания врача {username}: {driver.page_source[:500]}'


def _admin_create_quiz(driver, wait, title):
    driver.get(f'{BASE_URL}/admin/core/quiz/add/')
    wait.until(EC.presence_of_element_located((By.NAME, 'title')))
    driver.find_element(By.NAME, 'title').send_keys(title)
    driver.find_element(By.NAME, '_save').click()
    wait.until(EC.presence_of_element_located(
        (By.CSS_SELECTOR, 'ul.messagelist li.success')))


def _admin_reassign(driver, wait, search_term, target_doctor_id):
    # Отфильтровать пациентов по общему суффиксу в username.
    driver.get(f'{BASE_URL}/admin/core/patient/?q={search_term}')
    wait.until(EC.presence_of_element_located((By.ID, 'changelist-form')))

    boxes = driver.find_elements(By.NAME, '_selected_action')
    assert boxes, 'Пациенты не найдены в списке для переназначения'
    for b in boxes:
        if not b.is_selected():
            b.click()

    Select(driver.find_element(By.NAME, 'action')).select_by_value(
        'reassign_to_doctor')
    driver.find_element(By.CSS_SELECTOR, 'div.actions button[type="submit"]').click()

    # Промежуточная страница: выбрать целевого врача и подтвердить.
    wait.until(EC.presence_of_element_located((By.NAME, 'doctor')))
    Select(driver.find_element(By.NAME, 'doctor')).select_by_value(
        str(target_doctor_id))
    driver.find_element(By.NAME, 'apply').click()
    wait.until(EC.presence_of_element_located(
        (By.CSS_SELECTOR, 'ul.messagelist li.success')))


# ─── the workflow ────────────────────────────────────────────────────────

def test_admin_full_doctor_workflow(admin_login):
    driver = admin_login
    wait = WebDriverWait(driver, 15)
    sfx = uuid.uuid4().hex[:6]

    doc_a_user = f'doc_a_{sfx}'
    doc_b_user = f'doc_b_{sfx}'
    quiz_title = f'E2E тест {sfx}'

    # 1-2. Врачи B и A через админку.
    _admin_create_doctor(driver, wait, username=doc_b_user,
                         last_name='Сидоров', first_name='Пётр', clinic='Клиника B')
    _admin_create_doctor(driver, wait, username=doc_a_user,
                         last_name='Иванов', first_name='Иван', clinic='Клиника A')

    token_a = _doctor_token(doc_a_user, DOC_PASS)
    token_b = _doctor_token(doc_b_user, DOC_PASS)
    doc_b_id = requests.get(f'{API}/doctors/me', headers=_auth(token_b),
                            timeout=10).json()['id']

    # 3. Пациенты врачу A (API — в админке нет формы создания пациента).
    patient_ids = []
    for i in (1, 2):
        r = requests.post(
            f'{API}/doctors/patients', headers=_auth(token_a),
            json={'username': f'pat{i}_{sfx}', 'password': PAT_PASS,
                  'last_name': f'Пациентов{i}', 'first_name': 'Тест'},
            timeout=10,
        )
        r.raise_for_status()
        patient_ids.append(r.json()['id'])
    pat1_id = patient_ids[0]

    # 4. Перевод A → B через admin action.
    _admin_reassign(driver, wait, sfx, doc_b_id)

    # Проверяем перевод через API: пациенты теперь у врача B.
    b_patients = requests.get(f'{API}/doctors/me/patients', headers=_auth(token_b),
                              timeout=10).json()
    b_patient_ids = {p['id'] for p in b_patients}
    assert set(patient_ids) <= b_patient_ids, 'Перевод пациентов не сработал'

    # 5. Тест через админку.
    _admin_create_quiz(driver, wait, quiz_title)

    # 6. Назначение теста и сброс пароля через API (это и пишет логи).
    quizzes = requests.get(f'{API}/doctors/quizzes', headers=_auth(token_b),
                           timeout=10).json()
    quiz_id = next(q['id'] for q in quizzes if q['title'] == quiz_title)

    r = requests.post(
        f'{API}/doctors/patients/{pat1_id}/assign-quiz',
        headers=_auth(token_b), json={'quiz_id': quiz_id}, timeout=10)
    assert r.status_code == 200, f'assign failed: {r.status_code} {r.text}'

    r = requests.post(
        f'{API}/doctors/patients/{pat1_id}/reset-password',
        headers=_auth(token_b), json={'new_password': 'BrandNewPass99'}, timeout=10)
    assert r.status_code == 200, f'reset failed: {r.status_code} {r.text}'

    # 7. Читаем журнал действий врача B в админке.
    driver.get(f'{BASE_URL}/admin/core/doctor/{doc_b_id}/logs/')
    wait.until(EC.presence_of_element_located((By.ID, 'content')))
    page = driver.page_source
    assert 'Назначен тест' in page, 'В журнале врача нет записи о назначении'
    assert 'Сброс пароля' in page, 'В журнале врача нет записи о сбросе пароля'

    # ...и лог пациента (пометка о смене пароля, без самого пароля).
    driver.get(f'{BASE_URL}/admin/core/patient/{pat1_id}/logs/')
    wait.until(EC.presence_of_element_located((By.ID, 'content')))
    patient_page = driver.page_source
    assert 'Пароль изменён врачом' in patient_page, \
        'В логе пациента нет пометки о смене пароля'
    assert 'BrandNewPass99' not in patient_page, 'Пароль не должен быть в логе!'
