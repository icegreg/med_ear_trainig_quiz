#!/usr/bin/env bash
# Восстановление TNOISE из бэкапа, созданного backup.sh.
# ВНИМАНИЕ: перезаписывает текущую БД и медиа. Делайте на остановленном web
# (или сразу после разворачивания чистого сервера).
#
#   MODE=docker  (по умолчанию) | MODE=native
#
# Источник — локальный архив или объект S3:
#   deploy/scripts/restore.sh /var/backups/tnoise/tnoise-backup-YYYYmmdd-HHMMSS.tar.gz
#   deploy/scripts/restore.sh s3://bucket/tnoise/backups/tnoise-backup-...tar.gz
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MODE="${MODE:-docker}"
SRC="${1:-}"
export PROJECT_ROOT

[ -n "$SRC" ] || { echo "Использование: $0 <путь-к-архиву|s3://...>"; exit 1; }

# shellcheck disable=SC1091
set -a; . "$PROJECT_ROOT/.env"; set +a
COMPOSE="docker compose -f $PROJECT_ROOT/deploy/docker/docker-compose.prod.yml --env-file $PROJECT_ROOT/.env"

STAGE="$(mktemp -d)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

# ── Достаём архив (S3 или локально) ──
if [[ "$SRC" == s3://* ]]; then
    ep=""; [ -n "${S3_ENDPOINT:-}" ] && ep="--endpoint-url $S3_ENDPOINT"
    echo ">>> Скачиваю из S3: $SRC"
    # shellcheck disable=SC2086
    aws s3 cp "$SRC" "$STAGE/backup.tar.gz" $ep
    ARCHIVE="$STAGE/backup.tar.gz"
else
    ARCHIVE="$SRC"
fi

echo ">>> Распаковываю $ARCHIVE"
tar xzf "$ARCHIVE" -C "$STAGE"

read -r -p ">>> Это ПЕРЕЗАПИШЕТ базу $POSTGRES_DB и медиа. Продолжить? [y/N] " ans
[ "$ans" = "y" ] || { echo "Отменено."; exit 0; }

# ── 1. PostgreSQL ──
echo ">>> Восстанавливаю БД…"
if [ "$MODE" = "native" ]; then
    gunzip -c "$STAGE/db.sql.gz" | PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "${POSTGRES_HOST:-127.0.0.1}" -p "${POSTGRES_PORT:-5432}" \
        -U "$POSTGRES_USER" "$POSTGRES_DB"
else
    gunzip -c "$STAGE/db.sql.gz" | $COMPOSE exec -T db psql -U "$POSTGRES_USER" "$POSTGRES_DB"
fi

# ── 2. Медиа ──
if [ -f "$STAGE/media.tar.gz" ]; then
    echo ">>> Восстанавливаю media…"
    if [ "$MODE" = "native" ]; then
        MEDIA_DIR="${MEDIA_DIR:-$PROJECT_ROOT/server/media}"
        tar xzf "$STAGE/media.tar.gz" -C "$(dirname "$MEDIA_DIR")"
    else
        $COMPOSE exec -T web sh -c 'rm -rf /app/media/* && tar xzf - -C /app' < "$STAGE/media.tar.gz"
    fi
fi

# ── 3. client_logs ──
if [ -f "$STAGE/client_logs.tar.gz" ]; then
    echo ">>> Восстанавливаю client_logs…"
    if [ "$MODE" = "native" ]; then
        LOGS_DIR="${CLIENT_LOGS_DIR:-$PROJECT_ROOT/server/client_logs}"
        tar xzf "$STAGE/client_logs.tar.gz" -C "$(dirname "$LOGS_DIR")"
    else
        $COMPOSE exec -T web sh -c 'tar xzf - -C /app' < "$STAGE/client_logs.tar.gz"
    fi
fi

echo ">>> Восстановление завершено."
echo "    config.tar.gz внутри архива НЕ применяется автоматически —"
echo "    .env и конфиги разверните вручную при необходимости."
echo "    Если восстанавливали дефолтный релиз, при первом изменении реестра"
echo "    latest.apk пересоберётся сигналами; можно и вручную:"
echo "      $COMPOSE exec web python manage.py releases set-default <версия>"
