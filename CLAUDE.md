# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Medical hearing test platform (платформа тестирования слуха). Monorepo with three components:

| Component | Tech Stack | Target |
|-----------|-----------|--------|
| `patient_app/` | Flutter | Android / Web |
| `server/` | Django Ninja + PostgreSQL | Backend + Admin |
| `doctor_app/` | Flutter | Web |

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

### Локальная разработка (сервер)
```bash
cd server/
source ../server_venv/bin/activate
python manage.py migrate
python manage.py runserver
```

### Server tests
```bash
cd server/ && source ../server_venv/bin/activate

python manage.py test core.tests                    # все
python manage.py test core.tests.test_auth           # один файл
python manage.py test core.tests.test_auth.DeviceTokenAuthTest.test_obtain_device_token_success  # один метод
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
