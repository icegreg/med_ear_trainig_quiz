# Medical Hearing Test Platform

Платформа тестирования слуха: серверная часть (Django Ninja + PostgreSQL), приложение пациента (Flutter), приложение врача (Flutter).

## Быстрый старт

```bash
# 1. Собрать Flutter web-приложение
cd patient_app && flutter build web --dart-define=FLAVOR=dev && cd ..

# 2. Поднять всё в Docker
cp .env.example .env
docker compose up -d --build

# 3. Создать суперпользователя
docker compose exec web python manage.py createsuperuser
```

Открыть:
- **http://localhost** — приложение пациента
- **http://localhost/api/docs** — Swagger UI
- **http://localhost/admin** — Django-админка

## Генератор тестовых данных

Management-команда `generate_test_data` создаёт врачей, пациентов и назначает им тесты.

### Параметры

| Параметр | По умолчанию | Описание |
|----------|-------------|----------|
| `--doctors` | 5 | Количество врачей |
| `--patients-per-doctor` | 5 | Среднее кол-во пациентов на врача |
| `--quizzes-min` | 3 | Мин. кол-во тестов на пациента |
| `--quizzes-max` | 6 | Макс. кол-во тестов на пациента |
| `--questions-min` | 3 | Мин. кол-во вопросов в тесте |
| `--questions-max` | 10 | Макс. кол-во вопросов в тесте |
| `--existing` | — | Не создавать новых, добавить тесты существующим |
| `--patients` | все | Список username через запятую (с `--existing`) |
| `--output-dir` | `.` | Папка для CSV-файлов с credentials |

### Примеры

```bash
# Через Docker
docker compose exec web python manage.py generate_test_data
docker compose exec web python manage.py generate_test_data --output-dir /app

# Локально
cd server && source ../server_venv/bin/activate
python manage.py generate_test_data

# Кастомные параметры
python manage.py generate_test_data --doctors 3 --patients-per-doctor 10 \
    --quizzes-min 2 --quizzes-max 8 --questions-min 5 --questions-max 15

# Добавить тесты всем существующим пациентам
python manage.py generate_test_data --existing

# Добавить тесты конкретным пациентам
python manage.py generate_test_data --existing --patients patient_1,patient_3
```

### Выходные файлы

- `doctors_credentials.csv` — логины, пароли, ID и ФИО врачей
- `patients_credentials.csv` — логины, пароли, ID пациентов и назначенные врачи

По умолчанию файлы создаются в рабочей директории (`/app` внутри контейнера). Чтобы скопировать их из Docker-контейнера на хост:

```bash
docker compose cp web:/app/doctors_credentials.csv .
docker compose cp web:/app/patients_credentials.csv .
```

## Тестирование

```bash
# Серверные тесты
docker compose exec web python manage.py test core.tests

# Flutter E2E тесты (требует запущенный docker compose)
cd patient_app && flutter test test/api_integration_test.dart
```
