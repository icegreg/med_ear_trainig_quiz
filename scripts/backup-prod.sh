#!/usr/bin/env bash
# Бэкап self-hosted прода (VPS): БД PostgreSQL + media + staticfiles + client_logs + .env.prod.
#
# Запускать НА СЕРВЕРЕ от пользователя deploy:
#   ~/med_ear_trainig_quiz/scripts/backup-prod.sh
#
# Переменные окружения (все опциональны):
#   STACK_DIR   каталог стека            (по умолчанию ~/med_ear_trainig_quiz)
#   BACKUP_DIR  куда складывать архивы   (по умолчанию ~/backups)
#   KEEP_DAYS   сколько дней хранить     (по умолчанию 14; 0 — не удалять)
#
# Что получается в $BACKUP_DIR/<UTC-таймштамп>/:
#   db.dump          — pg_dump -Fc (восстановление через pg_restore)
#   media.tar.gz     — том media_data (APK-релизы, аудиофайлы)
#   static.tar.gz    — том static_data (collectstatic; воспроизводим, но пусть будет)
#   client_logs.tar.gz — том client_logs_data
#   env.prod         — секреты стека (chmod 600!)
#   MANIFEST.txt     — версия прода, размеры, sha256
#
# Скрипт НЕ трогает работающие контейнеры: pg_dump идёт онлайн, тома читаются
# одноразовым alpine-контейнером в режиме ro.

set -euo pipefail

STACK_DIR="${STACK_DIR:-$HOME/med_ear_trainig_quiz}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"

cd "$STACK_DIR"

# Имя compose-проекта = имя каталога; тома называются <project>_<volume>.
PROJECT="$(basename "$STACK_DIR" | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')"

# .env.prod даёт POSTGRES_DB/POSTGRES_USER; пароль pg_dump не нужен —
# ходим внутрь контейнера db как peer-пользователь postgres-образа.
# shellcheck disable=SC1091
set -a; . ./.env.prod; set +a
: "${POSTGRES_DB:?POSTGRES_DB не задан в .env.prod}"
: "${POSTGRES_USER:?POSTGRES_USER не задан в .env.prod}"

STAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
DEST="$BACKUP_DIR/$STAMP"
mkdir -p "$DEST"
chmod 700 "$BACKUP_DIR" "$DEST"

log() { printf '[backup %s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# ── Контейнер БД ищем по label'ам compose, а не по имени файла: набор
#    -f оверрайдов меняется при переезде на HTTPS, а проект остаётся тем же.
DB_CID="$(docker ps -q --filter "label=com.docker.compose.project=$PROJECT" \
                       --filter "label=com.docker.compose.service=db")"
[ -n "$DB_CID" ] || { echo "Контейнер db не найден (проект $PROJECT). Стек поднят?" >&2; exit 1; }

log "pg_dump $POSTGRES_DB -> db.dump"
docker exec -i "$DB_CID" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc > "$DEST/db.dump"

# ── Тома: media / static / client_logs ────────────────────────────────────
dump_volume() {
    local vol="$1" out="$2"
    if ! docker volume inspect "$vol" >/dev/null 2>&1; then
        log "том $vol отсутствует — пропускаю"
        return 0
    fi
    log "$vol -> $out"
    docker run --rm \
        -v "$vol":/data:ro \
        -v "$DEST":/backup \
        alpine:3.20 tar czf "/backup/$out" -C /data .
}

dump_volume "${PROJECT}_media_data"       media.tar.gz
dump_volume "${PROJECT}_static_data"      static.tar.gz
dump_volume "${PROJECT}_client_logs_data" client_logs.tar.gz

# Архивы пишет root внутри контейнера — возвращаем владение хостовому юзеру.
docker run --rm -v "$DEST":/backup alpine:3.20 \
    chown -R "$(id -u):$(id -g)" /backup

# ── Секреты и метаданные ─────────────────────────────────────────────────
log "env.prod + MANIFEST.txt"
cp .env.prod "$DEST/env.prod"
chmod 600 "$DEST/env.prod"

{
    echo "backup: $STAMP (UTC)"
    echo "host:   $(hostname) / $(id -un)"
    echo "project: $PROJECT"
    echo "db:     $POSTGRES_DB (user $POSTGRES_USER)"
    echo
    echo "--- DEPLOYED_VERSION ---"
    cat DEPLOYED_VERSION 2>/dev/null || echo "(нет файла)"
    echo
    echo "--- sha256 ---"
    (cd "$DEST" && sha256sum ./* 2>/dev/null | grep -v MANIFEST)
    echo
    echo "--- размеры ---"
    (cd "$DEST" && du -h ./*)
} > "$DEST/MANIFEST.txt"

chmod 600 "$DEST"/*

# ── Ротация ──────────────────────────────────────────────────────────────
if [ "$KEEP_DAYS" -gt 0 ]; then
    log "ротация: удаляю бэкапы старше $KEEP_DAYS дней"
    find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime "+$KEEP_DAYS" \
        -exec rm -rf {} + 2>/dev/null || true
fi

log "готово: $DEST ($(du -sh "$DEST" | cut -f1))"
