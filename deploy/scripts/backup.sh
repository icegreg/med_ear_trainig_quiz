#!/usr/bin/env bash
# Бэкап данных TNOISE: PostgreSQL + медиа (аудио и APK-релизы) + client_logs +
# конфиги/секреты. Пишет один архив в BACKUP_DIR, опционально выгружает в S3,
# чистит старые бэкапы по BACKUP_KEEP_DAYS.
#
#   MODE=docker  (по умолчанию) — данные берутся из docker-стека.
#   MODE=native               — данные берутся с диска / локального PostgreSQL.
#
# Все параметры читаются из .env в корне проекта (см. deploy/env/prod.env.example):
#   POSTGRES_*, BACKUP_DIR, BACKUP_KEEP_DAYS, S3_ENABLED, S3_BUCKET, S3_PREFIX,
#   S3_ENDPOINT, AWS_* .
#
# Примеры:
#   deploy/scripts/backup.sh
#   MODE=native deploy/scripts/backup.sh
#   # по расписанию: cron/systemd-timer — см. docs/deploy/README.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MODE="${MODE:-docker}"
export PROJECT_ROOT

# shellcheck disable=SC1091
set -a; . "$PROJECT_ROOT/.env"; set +a

BACKUP_DIR="${BACKUP_DIR:-/var/backups/tnoise}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
TS="$(date +%Y%m%d-%H%M%S)"
STAGE="$(mktemp -d)"
ARCHIVE="$BACKUP_DIR/tnoise-backup-$TS.tar.gz"
COMPOSE="docker compose -f $PROJECT_ROOT/deploy/docker/docker-compose.prod.yml --env-file $PROJECT_ROOT/.env"

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$BACKUP_DIR"
echo ">>> [$MODE] Бэкап в $ARCHIVE"

# ── 1. PostgreSQL ──
echo ">>> pg_dump ($POSTGRES_DB)…"
if [ "$MODE" = "native" ]; then
    PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
        -h "${POSTGRES_HOST:-127.0.0.1}" -p "${POSTGRES_PORT:-5432}" \
        -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip > "$STAGE/db.sql.gz"
else
    $COMPOSE exec -T db pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
        | gzip > "$STAGE/db.sql.gz"
fi

# ── 2. Медиа (аудио-файлы + APK-релизы) ──
echo ">>> media…"
if [ "$MODE" = "native" ]; then
    MEDIA_DIR="${MEDIA_DIR:-$PROJECT_ROOT/server/media}"
    tar czf "$STAGE/media.tar.gz" -C "$(dirname "$MEDIA_DIR")" "$(basename "$MEDIA_DIR")" 2>/dev/null || \
        echo "    (media пуст или отсутствует — пропускаю)"
else
    $COMPOSE exec -T web tar czf - -C /app media > "$STAGE/media.tar.gz"
fi

# ── 3. Клиентские логи пациентов ──
echo ">>> client_logs…"
if [ "$MODE" = "native" ]; then
    LOGS_DIR="${CLIENT_LOGS_DIR:-$PROJECT_ROOT/server/client_logs}"
    [ -d "$LOGS_DIR" ] && tar czf "$STAGE/client_logs.tar.gz" \
        -C "$(dirname "$LOGS_DIR")" "$(basename "$LOGS_DIR")" || \
        echo "    (client_logs отсутствует — пропускаю)"
else
    $COMPOSE exec -T web tar czf - -C /app client_logs > "$STAGE/client_logs.tar.gz" 2>/dev/null || \
        echo "    (client_logs пуст — пропускаю)"
fi

# ── 4. Конфиги и секреты ──
echo ">>> configs (.env, nginx, compose, systemd)…"
CFG="$STAGE/config"; mkdir -p "$CFG"
cp "$PROJECT_ROOT/.env" "$CFG/.env" 2>/dev/null || true
cp -r "$PROJECT_ROOT/deploy" "$CFG/deploy" 2>/dev/null || true
# Нативные конфиги, если лежат в системных путях:
[ -f /etc/nginx/sites-available/tnoise.conf ] && cp /etc/nginx/sites-available/tnoise.conf "$CFG/" || true
[ -f /etc/systemd/system/tnoise-web.service ] && cp /etc/systemd/system/tnoise-web.service "$CFG/" || true
tar czf "$STAGE/config.tar.gz" -C "$STAGE" config && rm -rf "$CFG"

# ── 5. Собираем единый архив ──
echo ">>> Пакую архив…"
tar czf "$ARCHIVE" -C "$STAGE" .
SIZE="$(du -h "$ARCHIVE" | cut -f1)"
echo ">>> Локальный бэкап готов: $ARCHIVE ($SIZE)"

# ── 6. Опциональная выгрузка в S3 ──
if [ "${S3_ENABLED:-false}" = "true" ]; then
    [ -n "${S3_BUCKET:-}" ] || { echo "!!! S3_ENABLED=true, но S3_BUCKET пуст"; exit 1; }
    ep=""; [ -n "${S3_ENDPOINT:-}" ] && ep="--endpoint-url $S3_ENDPOINT"
    dest="s3://$S3_BUCKET/${S3_PREFIX:-tnoise/backups}/$(basename "$ARCHIVE")"
    echo ">>> Выгружаю в $dest…"
    # shellcheck disable=SC2086
    aws s3 cp "$ARCHIVE" "$dest" $ep
    echo ">>> Выгружено в S3."
fi

# ── 7. Ротация локальных бэкапов ──
echo ">>> Чищу локальные бэкапы старше $KEEP_DAYS дней…"
find "$BACKUP_DIR" -name 'tnoise-backup-*.tar.gz' -type f -mtime "+$KEEP_DAYS" -print -delete || true

echo ">>> Бэкап завершён."
echo "    Для S3 ротацию удобнее настроить lifecycle-политикой бакета"
echo "    (удаление объектов старше $KEEP_DAYS дней)."
