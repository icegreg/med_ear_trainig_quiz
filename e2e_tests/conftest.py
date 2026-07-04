"""Selenium E2E test fixtures for Django admin."""
import os

import pytest
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

BASE_URL = os.environ.get('E2E_BASE_URL', 'http://localhost')
ADMIN_USER = os.environ.get('E2E_ADMIN_USER', 'admin')
ADMIN_PASS = os.environ.get('E2E_ADMIN_PASS', 'admin')


@pytest.fixture(scope='session')
def driver():
    """Chrome WebDriver (headless по умолчанию, --no-headless для обычного)."""
    opts = Options()
    if os.environ.get('E2E_HEADLESS', '1') == '1':
        opts.add_argument('--headless=new')
    opts.add_argument('--no-sandbox')
    opts.add_argument('--disable-dev-shm-usage')
    opts.add_argument('--window-size=1280,1024')
    # В headed-режиме Chrome показывает всплывашку менеджера паролей, которая
    # перехватывает клик по форме логина — отключаем.
    opts.add_experimental_option('prefs', {
        'credentials_enable_service': False,
        'profile.password_manager_enabled': False,
    })

    drv = webdriver.Chrome(options=opts)
    drv.implicitly_wait(5)
    yield drv
    drv.quit()


@pytest.fixture
def admin_login(driver):
    """Логин в Django admin. Идемпотентно: driver сессионный, между тестами
    сессия уже авторизована — тогда логин пропускаем."""
    wait = WebDriverWait(driver, 10)
    driver.get(f'{BASE_URL}/admin/')
    wait.until(EC.presence_of_element_located((By.TAG_NAME, 'body')))

    # Если формы логина нет — уже авторизованы.
    if not driver.find_elements(By.NAME, 'username'):
        return driver

    driver.find_element(By.NAME, 'username').clear()
    driver.find_element(By.NAME, 'username').send_keys(ADMIN_USER)
    driver.find_element(By.NAME, 'password').clear()
    driver.find_element(By.NAME, 'password').send_keys(ADMIN_PASS)
    driver.find_element(By.CSS_SELECTOR, 'input[type="submit"]').click()
    # Логин успешен только когда мы ушли со страницы /login (url_contains('/admin/')
    # ошибочно матчит и саму /admin/login/).
    wait.until(lambda d: '/login' not in d.current_url)
    return driver
