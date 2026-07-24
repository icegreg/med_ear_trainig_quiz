# Продовая установка TNOISE

Руководство по развёртыванию платформы в проде на **Ubuntu 24.04**,
**Debian 12** и **Debian 13** двумя способами — **в Docker** (рекомендуется) и
**нативно (без Docker)**. Продовый домен — **tnoise.com**, TLS — Let's Encrypt.

Предполагается, что SSH-доступ на сервер (обычный sudo-пользователь) уже есть.

> Coolify используется только на препроде. Прод разворачивается вручную по этой
> инструкции; артефакты `Dockerfile.coolify` / `docker-compose.coolify.yml` —
> лишь референс, здесь не используются.

## Содержание
- [Что мы разворачиваем](#что-мы-разворачиваем)
- [Предварительные требования](#предварительные-требования)
- [Вариант A — Docker](#вариант-a--docker-рекомендуется)
- [Вариант B — без Docker (нативно)](#вариант-b--без-docker-нативно)
- [Различия между ОС](#различия-между-ос)
- [TLS / Let's Encrypt](#tls--lets-encrypt)
- [Бэкап данных](#бэкап-данных)
- [Старт и останов](#старт-и-останов)
- [Обновление версии](#обновление-версии)
- [Проверочный чеклист](#проверочный-чеклист)

---

## Что мы разворачиваем

| Слой | Что | Порт |
|------|-----|------|
| nginx | TLS-терминация, раздача Flutter web (patient/doctor), статики и APK-релизов, проксирование на Django | 80/443 |
| Django (gunicorn) | API, админка, защищённая раздача аудио и документации | 8000 (внутренний) |
| PostgreSQL | все данные приложения | 5432 (внутренний) |
| certbot | выпуск и автопродление сертификата Let's Encrypt | — |

**Пути раздачи:**
- `/` — приложение пациента, `/doctors/` — приложение врача (Flutter web).
- `/api/`, `/admin/`, `/docs/` — Django.
- `/static/` — статика Django, `/releases/` — APK (публично, без auth;
  дефолт — `/releases/latest.apk`).
- `/media/` — аудио, проксируется на Django (проверка auth).

Все артефакты прод-развёртывания лежат в каталоге [`deploy/`](../../deploy):

```
deploy/
├── env/prod.env.example        # шаблон .env
├── docker/
│   ├── docker-compose.prod.yml # db + web + nginx + certbot
│   └── nginx.prod.conf         # TLS-конфиг nginx (docker)
├── native/
│   ├── gunicorn.conf.py
│   ├── tnoise-web.service       # systemd-юнит
│   └── nginx-tnoise.conf        # nginx-сайт (native)
└── scripts/
    ├── init-letsencrypt.sh      # первичный выпуск TLS (docker)
    ├── start.sh  / stop.sh      # старт/останов (docker и native)
    └── backup.sh / restore.sh   # бэкап/восстановление
```

---

## Предварительные требования

1. **DNS.** A-записи `tnoise.com` и `www.tnoise.com` указывают на IP сервера
   (обязательно ДО выпуска сертификата).
2. **Файрвол.** Открыты входящие 80 и 443 (и 22 для SSH). PostgreSQL наружу не
   публикуется.
   ```bash
   sudo ufw allow OpenSSH
   sudo ufw allow 80,443/tcp
   sudo ufw enable
   ```
3. **Секреты.** Сгенерируйте заранее:
   ```bash
   # DJANGO_SECRET_KEY (50+ символов)
   python3 -c "import secrets; print(secrets.token_urlsafe(64))"
   # POSTGRES_PASSWORD
   openssl rand -base64 24
   ```
4. **Код.** Склонируйте репозиторий (для Docker — в любой каталог, для native —
   в `/opt/tnoise`):
   ```bash
   sudo git clone <repo-url> /opt/tnoise && cd /opt/tnoise
   ```

---

## Вариант A — Docker (рекомендуется)

Единственный способ, одинаковый на всех трёх ОС (образ несёт Python 3.12, так
что версия системного Python не важна).

### A1. Установить Docker Engine + compose

```bash
# Ubuntu 24.04 / Debian 12 / Debian 13 — официальный скрипт
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"   # перелогиниться после этого
```

Проверка: `docker compose version`.

### A2. Подготовить `.env`

```bash
cd /opt/tnoise                     # или ваш каталог с проектом
cp deploy/env/prod.env.example .env
$EDITOR .env                       # заполнить CHANGE_ME, домены = tnoise.com
```
Для Docker оставьте `POSTGRES_HOST=db`.

### A3. Собрать Flutter web (FLAVOR=prod)

Прод-бандлы собираются с `FLAVOR=prod` (относительный `/api`, same-origin).
Если Flutter SDK на хосте нет — собираем в контейнере:

```bash
docker run --rm -v "$PWD/patient_app":/app -w /app instrumentisto/flutter:3.24 \
  sh -c "flutter pub get && flutter build web --dart-define=FLAVOR=prod --release"

docker run --rm -v "$PWD/doctor_app":/app -w /app instrumentisto/flutter:3.24 \
  sh -c "flutter pub get && flutter build web --base-href=/doctors/ --dart-define=FLAVOR=prod --release"
```
Артефакты появятся в `patient_app/build/web` и `doctor_app/build/web` — их
монтирует nginx.

### A4. Выпустить сертификат Let's Encrypt (первый раз)

DNS уже должен указывать на сервер. Скрипт поднимает nginx с временным
самоподписанным сертификатом, получает настоящий и перезагружает nginx:

```bash
deploy/scripts/init-letsencrypt.sh
```
> Для отладки без расхода лимитов LE: `CERTBOT_STAGING=1 deploy/scripts/init-letsencrypt.sh`,
> затем повторить без `CERTBOT_STAGING`.

### A5. Запустить стек

```bash
deploy/scripts/start.sh
```
`web` при старте сам выполняет `collectstatic` и `migrate`. Создать
администратора:
```bash
docker compose -f deploy/docker/docker-compose.prod.yml --env-file .env \
  exec web python manage.py createsuperuser
```

### A6. Проверить

```bash
curl -I https://tnoise.com               # 200, приложение пациента
curl -I https://tnoise.com/doctors/      # 200, приложение врача
curl -I https://tnoise.com/api/docs      # 200, Swagger
curl -I https://tnoise.com/admin/        # 302/200
```

---

## Вариант B — без Docker (нативно)

> **Важно про Python.** Django 6 требует **Python ≥ 3.12**.
> - **Ubuntu 24.04** — Python 3.12 из коробки ✅
> - **Debian 13 (trixie)** — Python 3.13 из коробки ✅
> - **Debian 12 (bookworm)** — системный Python 3.11 ❌ не подходит. Либо
>   ставьте Python 3.12 отдельно (pyenv / сборка из исходников), либо
>   используйте **Вариант A (Docker)** — он это обходит. Ниже команды для 3.12.

### B1. Системные пакеты

**Ubuntu 24.04 / Debian 13:**
```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-dev build-essential \
    libpq-dev postgresql nginx certbot python3-certbot-nginx git
```
**Debian 12:** то же, но сначала обеспечьте Python 3.12 (pyenv/из исходников) и
используйте его вместо `python3` в шагах ниже.

### B2. PostgreSQL

```bash
sudo -u postgres psql <<'SQL'
CREATE USER med_ear_user WITH PASSWORD 'СЮДА_ПАРОЛЬ_ИЗ_ENV';
CREATE DATABASE med_ear_prod OWNER med_ear_user;
SQL
```

### B3. Пользователь, код, venv

```bash
sudo useradd --system --home /opt/tnoise --shell /usr/sbin/nologin tnoise || true
sudo git clone <repo-url> /opt/tnoise
cd /opt/tnoise

sudo python3 -m venv venv
sudo venv/bin/pip install --upgrade pip
sudo venv/bin/pip install -r server/requirements.txt gunicorn
sudo chown -R tnoise:tnoise /opt/tnoise
```

### B4. `.env`

```bash
sudo cp deploy/env/prod.env.example .env
sudo $EDITOR .env
```
Для нативной установки поставьте **`POSTGRES_HOST=127.0.0.1`**.

### B5. Flutter web (FLAVOR=prod)

Соберите бандлы (командой из [A3](#a3-собрать-flutter-web-flavorprod) через
Docker, либо установленным Flutter SDK). Результат должен лежать в
`/opt/tnoise/patient_app/build/web` и `/opt/tnoise/doctor_app/build/web`.

### B6. Статика, миграции, суперпользователь

```bash
cd /opt/tnoise/server
set -a; . /opt/tnoise/.env; set +a
sudo -u tnoise -E ../venv/bin/python manage.py collectstatic --noinput
sudo -u tnoise -E ../venv/bin/python manage.py migrate --noinput
sudo -u tnoise -E ../venv/bin/python manage.py createsuperuser
```

### B7. gunicorn как systemd-сервис

```bash
sudo cp deploy/native/tnoise-web.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tnoise-web.service
sudo systemctl status tnoise-web.service --no-pager
```

### B8. nginx + TLS

```bash
sudo cp deploy/native/nginx-tnoise.conf /etc/nginx/sites-available/tnoise.conf
sudo ln -sf /etc/nginx/sites-available/tnoise.conf /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

# Выпуск сертификата (certbot сам впишет 443 и редирект 80→443):
sudo certbot --nginx -d tnoise.com -d www.tnoise.com \
    --email admin@tnoise.com --agree-tos --no-eff-email --redirect
```
Проверка — как в [A6](#a6-проверить).

---

## Различия между ОС

| | Ubuntu 24.04 | Debian 12 | Debian 13 |
|---|---|---|---|
| Системный Python | 3.12 ✅ | 3.11 ❌ (нужен 3.12) | 3.13 ✅ |
| Native-установка | напрямую | только с отдельным Python 3.12 или Docker | напрямую |
| Docker-установка | без нюансов | без нюансов | без нюансов |
| Пакеты certbot | `certbot python3-certbot-nginx` | то же | то же |
| Сервис PostgreSQL | `postgresql` | `postgresql` | `postgresql` |

Вывод: для Debian 12 **предпочтителен Docker**. Docker-путь идентичен на всех трёх.

---

## TLS / Let's Encrypt

- **Docker.** Первичный выпуск — `deploy/scripts/init-letsencrypt.sh`.
  Автопродление делает сервис `certbot` (проверка каждые 12 ч), nginx сам
  перезагружается раз в 6 ч и подхватывает новый сертификат. Ручная проверка:
  ```bash
  docker compose -f deploy/docker/docker-compose.prod.yml --env-file .env \
    run --rm certbot renew --dry-run
  ```
- **Native.** Сертификат ставит `certbot --nginx`. Автопродление уже настроено
  системным таймером `certbot.timer`:
  ```bash
  systemctl list-timers | grep certbot
  sudo certbot renew --dry-run
  ```

---

## Бэкап данных

### Что бэкапим

| Данные | Где (Docker) | Где (native) |
|--------|--------------|--------------|
| **PostgreSQL** — врачи, пациенты, тесты, результаты, назначения, токены, реестр релизов | том `postgres_data` | БД `med_ear_prod` |
| **Медиа** — аудио-файлы и APK-релизы (`media/releases`) | том `media_data` | `server/media` |
| **client_logs** — клиентские логи пациентов (только через админку) | том `client_logs_data` | `server/client_logs` |
| **Конфиги/секреты** — `.env`, `deploy/`, nginx- и systemd-конфиги | репозиторий/ФС | репозиторий/ФС |

> Статика (`staticfiles`) не бэкапится — пересоздаётся `collectstatic`.
> Сами сертификаты Let's Encrypt легко перевыпускаются, отдельно не храним.

### Скрипт бэкапа

`deploy/scripts/backup.sh` собирает **один архив**
`tnoise-backup-<дата>.tar.gz` (dump БД + tar медиа + client_logs + конфиги),
кладёт его в `BACKUP_DIR`, при `S3_ENABLED=true` выгружает в S3 и удаляет
локальные архивы старше `BACKUP_KEEP_DAYS`.

```bash
# Docker
deploy/scripts/backup.sh
# Native
MODE=native deploy/scripts/backup.sh
```

### По расписанию

Через cron (ежедневно в 3:30):
```bash
sudo crontab -e
# Docker:
30 3 * * * cd /opt/tnoise && ./deploy/scripts/backup.sh >> /var/log/tnoise-backup.log 2>&1
# Native:
30 3 * * * cd /opt/tnoise && MODE=native ./deploy/scripts/backup.sh >> /var/log/tnoise-backup.log 2>&1
```

### Выгрузка в S3

Пока бэкапы хранятся локально; выгрузка в S3 включается флагом в `.env`:
```
S3_ENABLED=true
S3_BUCKET=my-bucket
S3_PREFIX=tnoise/backups
S3_ENDPOINT=            # для не-AWS (Yandex/Selectel/Minio) указать endpoint
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=ru-central1
```
Требуется `aws-cli` (`sudo apt install awscli` или `pipx install awscli`).
Ротацию в S3 удобнее задать lifecycle-политикой бакета (удаление объектов
старше N дней), а не скриптом.

### Восстановление

```bash
# из локального архива
deploy/scripts/restore.sh /var/backups/tnoise/tnoise-backup-YYYYmmdd-HHMMSS.tar.gz
# из S3
deploy/scripts/restore.sh s3://my-bucket/tnoise/backups/tnoise-backup-....tar.gz
# native
MODE=native deploy/scripts/restore.sh <архив>
```
Скрипт перезаписывает БД и медиа (спрашивает подтверждение). `.env`/конфиги из
архива разворачиваются вручную.

---

## Старт и останов

```bash
# Docker
deploy/scripts/start.sh          # up -d --build
deploy/scripts/stop.sh           # down (тома с данными сохраняются)

# Native
MODE=native deploy/scripts/start.sh   # systemctl start tnoise-web + reload nginx
MODE=native deploy/scripts/stop.sh    # systemctl stop tnoise-web
```

---

## Обновление версии

```bash
cd /opt/tnoise
git pull
# пересобрать Flutter web (шаг A3), если менялись приложения

# Docker:
deploy/scripts/start.sh          # пересоберёт образ, применит миграции

# Native:
sudo venv/bin/pip install -r server/requirements.txt gunicorn
cd server && sudo -u tnoise -E ../venv/bin/python manage.py migrate --noinput
sudo -u tnoise -E ../venv/bin/python manage.py collectstatic --noinput
sudo systemctl restart tnoise-web.service
```
Реестр APK-релизов ведётся CLI (`manage.py releases`, см. корневой CLAUDE.md).

---

## Проверочный чеклист

- [ ] DNS `tnoise.com` / `www.tnoise.com` → IP сервера
- [ ] Открыты порты 80/443, PostgreSQL наружу закрыт
- [ ] `.env` заполнен, все `CHANGE_ME` заменены, `ENVIRONMENT=prod`
- [ ] Flutter web собран с `FLAVOR=prod`
- [ ] Сертификат выпущен, `https://tnoise.com` открывается без предупреждений
- [ ] `/`, `/doctors/`, `/api/docs`, `/admin/` отвечают
- [ ] Создан суперпользователь
- [ ] Бэкап отрабатывает (`backup.sh`) и восстановление проверено на копии
- [ ] Настроено расписание бэкапов (cron), при необходимости — выгрузка в S3
- [ ] Автопродление TLS проверено (`certbot renew --dry-run`)
