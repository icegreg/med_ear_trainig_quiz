# Бэкапы прод-стенда

Прод: VPS `159.195.156.249`, пользователь `deploy`, стек в `~/med_ear_trainig_quiz`
(compose-проект `med_ear_trainig_quiz`).

Всё делает скрипт [`scripts/backup-prod.sh`](../scripts/backup-prod.sh) — он лежит
на сервере в `~/med_ear_trainig_quiz/scripts/backup-prod.sh`.

## Что бэкапится

| Что | Откуда | Файл в бэкапе | Восстановимо иначе? |
|-----|--------|---------------|---------------------|
| PostgreSQL | контейнер `db`, `pg_dump -Fc` | `db.dump` | **нет** |
| Загруженные файлы | том `media_data` (аудио, APK-релизы) | `media.tar.gz` | **нет** |
| Логи клиентов | том `client_logs_data` | `client_logs.tar.gz` | **нет** |
| Секреты стека | `.env.prod` | `env.prod` | **нет** (SECRET_KEY, пароль БД) |
| Собранная статика | том `static_data` | `static.tar.gz` | да, `collectstatic` |

Метаданные (версия прода, sha256, размеры) — в `MANIFEST.txt`.

Сертификаты Let's Encrypt (том `letsencrypt`) намеренно **не** бэкапятся: их
дешевле перевыпустить, чем хранить приватные ключи в архивах. То же про
`postgres_data` целиком — логический дамп переносимее файлов кластера.

## Как сделать бэкап

```bash
ssh -i pr.key deploy@159.195.156.249
~/med_ear_trainig_quiz/scripts/backup-prod.sh
```

Результат — каталог `~/backups/<UTC-таймштамп>/` (права 700, файлы 600).
Стек при этом не останавливается: `pg_dump` работает онлайн, тома читаются
одноразовым `alpine`-контейнером в режиме `:ro`.

Настройки через переменные окружения:

```bash
BACKUP_DIR=/mnt/backups ~/med_ear_trainig_quiz/scripts/backup-prod.sh  # другой каталог
KEEP_DAYS=30 ~/med_ear_trainig_quiz/scripts/backup-prod.sh             # хранить 30 дней
KEEP_DAYS=0  ~/med_ear_trainig_quiz/scripts/backup-prod.sh             # не ротировать
```

По умолчанию бэкапы старше 14 дней удаляются.

## Копия за пределы сервера

Бэкап на том же диске, что и прод, спасает от «уронил таблицу», но не от потери
VPS. Забрать копию на рабочую машину:

```bash
scp -i pr.key -r deploy@159.195.156.249:'~/backups/2026-08-25T07-17-06Z' ~/backups/tnoise-prod/
```

В архиве лежит `env.prod` с боевыми секретами — не кладите такие копии в репозиторий
и в общие облачные папки.

## Расписание

Автозапуска сейчас нет. Cron пользователя `deploy` (root-прав у него нет,
systemd-таймер завести нельзя) — ежедневно в 03:20 по времени сервера:

```bash
ssh -i pr.key deploy@159.195.156.249
crontab -e
```

```cron
20 3 * * * /home/deploy/med_ear_trainig_quiz/scripts/backup-prod.sh >> /home/deploy/backups/backup.log 2>&1
```

Проверить, что задание встало: `crontab -l`. Смотреть результат: `tail ~/backups/backup.log`.

## Проверка бэкапа

Дамп, который никто не пробовал восстановить, — не бэкап. Быстрая проверка
целостности (не трогает прод-БД):

```bash
D=~/backups/2026-08-25T07-17-06Z
DB=$(docker ps -q --filter label=com.docker.compose.service=db)

# Дамп читается и содержит данные всех таблиц
docker exec -i $DB pg_restore --list < $D/db.dump | grep -c 'TABLE DATA'

# Архивы не побились
for f in media static client_logs; do gzip -t $D/$f.tar.gz && echo "$f ok"; done

# Контрольные суммы совпадают с зафиксированными при бэкапе
(cd $D && sha256sum -c <(grep -A99 'sha256' MANIFEST.txt | tail -n +2 | grep '^[0-9a-f]'))
```

Полноценная репетиция восстановления — поднять дамп в отдельную временную БД:

```bash
docker exec -i $DB createdb -U med_ear_user restore_test
docker exec -i $DB pg_restore -U med_ear_user -d restore_test < $D/db.dump
docker exec -i $DB psql -U med_ear_user -d restore_test -c 'SELECT count(*) FROM core_patient;'
docker exec -i $DB dropdb -U med_ear_user restore_test
```

## Восстановление

> Останавливает прод. Перед началом сделайте свежий бэкап текущего состояния —
> он понадобится, если что-то пойдёт не так.

```bash
cd ~/med_ear_trainig_quiz
D=~/backups/<таймштамп>

# 1. Погасить приложение, оставить только БД
docker compose -f docker-compose.prod.yml stop web nginx

# 2. Пересоздать базу из дампа
DB=$(docker ps -q --filter label=com.docker.compose.service=db)
docker exec -i $DB dropdb   -U med_ear_user med_ear_prod
docker exec -i $DB createdb -U med_ear_user med_ear_prod
docker exec -i $DB pg_restore -U med_ear_user -d med_ear_prod --no-owner < $D/db.dump

# 3. Вернуть тома (--force-recreate не нужен: тома монтируются по имени)
docker run --rm -v med_ear_trainig_quiz_media_data:/data -v $D:/backup:ro \
    alpine:3.20 sh -c 'rm -rf /data/* && tar xzf /backup/media.tar.gz -C /data'
docker run --rm -v med_ear_trainig_quiz_client_logs_data:/data -v $D:/backup:ro \
    alpine:3.20 sh -c 'rm -rf /data/* && tar xzf /backup/client_logs.tar.gz -C /data'

# 4. Секреты (только если восстанавливаете на чистый хост)
cp $D/env.prod .env.prod && cp .env.prod .env && chmod 600 .env.prod .env

# 5. Поднять обратно — collectstatic на старте пересоберёт static_data сам
docker compose -f docker-compose.prod.yml up -d
```

## История

- **2026-08-25** — первый бэкап: `~/backups/2026-08-25T07-17-06Z`
  (БД 9 МБ / 23 таблицы, media пустая — APK на прод ещё не заливали,
  static 1.5 МБ / 534 файла).
