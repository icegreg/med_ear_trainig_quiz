"""E2E: Django admin — CRUD категорий аудио."""
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

from conftest import BASE_URL


def test_admin_category_list(admin_login):
    """Список категорий доступен в админке."""
    driver = admin_login
    driver.get(f'{BASE_URL}/admin/core/audiocategory/')
    wait = WebDriverWait(driver, 10)
    wait.until(EC.presence_of_element_located((By.ID, 'result_list')))
    # Должна быть как минимум дефолтная категория "Общая"
    assert 'Общая' in driver.page_source


def test_admin_create_category(admin_login):
    """Создание категории через админку."""
    driver = admin_login
    driver.get(f'{BASE_URL}/admin/core/audiocategory/add/')
    wait = WebDriverWait(driver, 10)
    wait.until(EC.presence_of_element_located((By.NAME, 'name')))
    driver.find_element(By.NAME, 'name').send_keys('Selenium Test Category')
    driver.find_element(By.NAME, '_save').click()
    wait.until(EC.url_contains('/admin/core/audiocategory/'))
    assert 'Selenium Test Category' in driver.page_source


def test_admin_audiofile_list(admin_login):
    """Список аудиофайлов доступен, показывает категорию."""
    driver = admin_login
    driver.get(f'{BASE_URL}/admin/core/audiofile/')
    wait = WebDriverWait(driver, 10)
    # Страница загрузилась
    wait.until(EC.presence_of_element_located((By.ID, 'content')))
    # Должна отображаться колонка "Категория"
    assert 'Категория' in driver.page_source or 'category' in driver.page_source.lower()
