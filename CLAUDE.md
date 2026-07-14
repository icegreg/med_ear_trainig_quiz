# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Medical hearing test platform (платформа тестирования слуха). Monorepo with three components:

| Component | Tech Stack | Target |
|-----------|-----------|--------|
| `patient_app/` | Flutter | Android / Web |
| `server/` | Django Ninja + PostgreSQL | Backend + Admin |
| `doctor_app/` | Flutter | Web |

## Kaiten

Задачи этого проекта живут в Kaiten:
- Пространство: «Кабан», space_id = 809896
  (вложено в «Первое пространство» → каталог «EAR MED»)
- Основная доска задач: «Разработка», board_id = 1824519
  Колонки: Очередь (6303162) → Написание кода (6303163) →
  Тестирование (6303164) → Готово (6303165).
  Дорожки: «Обычный приоритет» (2291310), «Срочно» (2291311).
- Другие доски пространства: «⚡️Основные цели» (1824520), «Деплой» (1824909).

Типы карточек (`type_id` при создании):

| Тип | id | | Тип | id |
|-----|-----|---|-----|-----|
| Bug | 691947 | | Key results | 691967 |
| Feature | 691946 | | Разработка | 691968 |
| Card | 1 | | Маркетинг | 691969 |
| Concept | 691964 | | Менеджмент | 691970 |
| Legal | 691965 | | Epic | 691966 |

Баги заводи с `type_id = 691947` (Bug), фичи — с `691946` (Feature).

Когда я прошу «задачи», «что в работе», «бэклог» — бери карточки
именно из space_id 809896. Не опрашивай другие пространства без явной просьбы.
Для чтения используй инструменты kaiten (list_boards, list_cards, get_card).

На каждый найденный и починенный баг заводи карточку в «Разработке» — не
ограничивайся веткой и PR. Готовый код с открытым PR клади в «Тестирование»,
в описании давай ссылку на PR и ветку.

## Build & Run

### Docker (рекомендуемый способ)
```bash
# Собрать Flutter web + поднять всё
cd patient_app/ && flutter build web --dart-define=FLAVOR=dev && cd ..
cd doctor_app/ && flutter build web --base-href=/doctors/ --dart-define=FLAVOR=dev && cd ..
docker compose up -d --build

# http://localhost          — Patient app
# http://localhost/doctors/ — Doctor app
# http://localhost/api/docs — Swagger UI
# http://localhost/admin    — Django admin (admin/admin)
```

#### Сборка Flutter web без локального SDK (профиль `build`)
Если на хосте нет Flutter SDK, web-бандлы можно собрать в Docker
(образ `instrumentisto/flutter:3.24`). Артефакты попадают в те же
`./*/build/web`, которые монтирует nginx.
```bash
docker compose --profile build run --rm flutter-patient
docker compose --profile build run --rm flutter-doctor
docker compose up -d --build
```
Build-сервисы в конце делают `chown` на `HOST_UID:HOST_GID` (по умолчанию
`1000:1000`), чтобы артефакты не оставались root-owned. Если ваш UID/GID
отличается — задайте `HOST_UID`/`HOST_GID` (в `.env` или окружении).
Прод (Coolify) собирает Flutter иначе — внутри `Dockerfile.coolify`,
поэтому build-сервисы только для локальной разработки.

### Локальная разработка (сервер)
```bash
cd server/
source ../server_venv/bin/activate
python manage.py migrate
python manage.py runserver
```

### Server tests (PostgreSQL в docker)
Запускать только внутри docker-контейнера (там подключён PostgreSQL `db`).
SQLite не поддерживает case-insensitive поиск по кириллице (`icontains`).
```bash
docker compose exec web python manage.py test core.tests                # все
docker compose exec web python manage.py test core.tests.test_auth      # один файл
docker compose exec web python manage.py test core.tests.test_auth.DeviceTokenAuthTest.test_obtain_device_token_success  # один метод
```

### Flutter E2E tests (требует запущенный сервер)
```bash
# Patient app API tests
cd patient_app/
flutter test test/api_integration_test.dart

# Doctor app API tests
cd doctor_app/
flutter test test/api_integration_test.dart

# Flutter integration tests (Chrome)
cd doctor_app/ && flutter test integration_test --device-id chrome   # headless
cd patient_app/ && flutter test integration_test --device-id chrome  # headless
```

### Selenium E2E tests (требует запущенный Docker)
```bash
cd e2e_tests/
pip install -r requirements.txt
E2E_HEADLESS=1 pytest                    # headless Chrome
E2E_HEADLESS=0 pytest                    # обычный Chrome
```

### Генератор тестовых данных
```bash
cd server/ && source ../server_venv/bin/activate

# Дефолт: 5 врачей, 5 пациентов/врач, 3-6 тестов, 3-10 вопросов
python manage.py generate_test_data

# Кастомные параметры
python manage.py generate_test_data --doctors 3 --patients-per-doctor 10 \
    --quizzes-min 2 --quizzes-max 8 --questions-min 5 --questions-max 15

# Добавить тесты существующим пациентам (всем или выборочно)
python manage.py generate_test_data --existing
python manage.py generate_test_data --existing --patients patient_1,patient_3

# Указать папку для credential-файлов
python manage.py generate_test_data --output-dir /tmp
```
Генерирует `doctors_credentials.csv` и `patients_credentials.csv` с логинами/паролями.

### APK-релизы (дистрибуция пациентского приложения)
Реестр релизов APK привязан к стенду (у preprod и prod свои БД — flavor
константный, в модели `Release` не хранится). Все APK доступны **без пароля**.

- **Скачивание** (публично, без auth):
  - `GET /releases/latest.apk` — стабильная ссылка на дефолтный релиз
    (nginx раздаёт напрямую локально; на стендах Coolify — Django `serve_release`).
  - `GET /releases/<file>` — конкретный APK.
  - `GET /api/releases/` — список релизов; `GET /api/releases/latest` — дефолтный.
- **Админка**: раздел «Релизы APK» — список, загрузка, action «Сделать дефолтным»
  (`Release.set_default()` снимает прежний дефолт и обновляет `latest.apk`).
- **Сборка APK** (docker-композиция, профиль `build`):
  ```bash
  APK_FLAVOR=preprod docker compose --profile build run --rm apk-build
  docker compose exec web python manage.py register_release \
      --apk /app/media/releases/incoming/app-preprod-release.apk \
      --version-name 0.6.0 --version-code 2 --commit $(git rev-parse HEAD) --set-default
  ```
- **Автосборка**: CI job `build-apk` собирает release-APK (preprod+prod) при
  **push в main** и публикует артефактами; доставку на стенд (вызов
  `register_release`) выполняет деплой стенда.

## Architecture

### Authentication — dual scheme
- **Patients**: long-lived Device Token (obtained once via login/password, stored on device). Auth class: `DeviceTokenAuth` → sets `request.patient`.
- **Doctors**: JWT (access 24h + refresh 30d). Auth class: `DoctorJWTAuth` → sets `request.doctor`.
- Auth endpoints (`/api/auth/*`) are public. All other endpoints require auth via their respective scheme.
- Doctor registration is admin-only (no public endpoint).

### API routing (`core/api.py`)
Routers are split by domain in `core/routers/`:
- `/api/auth/` — public: device-token, doctor login/refresh
- `/api/patients/` — DeviceTokenAuth: profile, quizzes, results
- `/api/quizzes/` — DeviceTokenAuth: detail, audio files, submit
- `/api/doctors/` — DoctorJWTAuth: profile, patients, results, transfer

When a view returns an error status code (401, 403, 400), the response dict must be declared in the `response=` parameter, e.g. `response={200: OkSchema, 403: ErrorSchema}`. Django Ninja raises `ConfigError` otherwise.

### Key Domain Rules
- Quizzes are one-time only — re-submission returns 403
- QuizResult is immutable after creation
- Patient has FK to Doctor (one doctor at a time); transfer via `/api/doctors/transfer-patient`
- Doctor model has ФИО (last_name, first_name, patronymic) and optional clinic — registered through Django admin
- Deleting an AudioFile must NOT affect quiz results
- Battery threshold and volume level are configured in the Flutter app, not on the server

### Data Model
Core entities in `core/models.py`: Doctor, Patient, AudioFile, Quiz, QuizQuestion, PatientQuizAssignment (status: assigned/completed), QuizResult, DeviceToken.

### Test conventions
- All API tests must verify that non-auth endpoints return 401 without a token (`test_auth_required.py`)
- Base fixtures in `core/tests/helpers.py` — `APITestBase` provides doctor, patient, device_token, quiz, question, assignment
- Use `self.patient_headers()` / `self.doctor_headers()` for authenticated requests
