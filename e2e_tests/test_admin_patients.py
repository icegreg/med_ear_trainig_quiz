"""E2E: Django admin — пациенты."""
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

from conftest import BASE_URL


def test_admin_patient_list(admin_login):
    """Список пациентов доступен в админке."""
    driver = admin_login
    driver.get(f'{BASE_URL}/admin/core/patient/')
    wait = WebDriverWait(driver, 10)
    wait.until(EC.presence_of_element_located((By.ID, 'content')))
    assert 'Пациент' in driver.page_source


def test_admin_notification_list(admin_login):
    """Список уведомлений доступен в админке."""
    driver = admin_login
    driver.get(f'{BASE_URL}/admin/core/notification/')
    wait = WebDriverWait(driver, 10)
    wait.until(EC.presence_of_element_located((By.ID, 'content')))
    assert 'Уведомлен' in driver.page_source


def test_admin_doctor_list(admin_login):
    """Список врачей доступен в админке."""
    driver = admin_login
    driver.get(f'{BASE_URL}/admin/core/doctor/')
    wait = WebDriverWait(driver, 10)
    wait.until(EC.presence_of_element_located((By.ID, 'content')))
    assert 'Врач' in driver.page_source
