#!/usr/bin/env bash
# Останов прод-стека TNOISE.
#
#   MODE=docker  (по умолчанию) — docker compose down (тома сохраняются).
#   MODE=native               — остановить systemd-юнит gunicorn.
#
# Примеры:
#   deploy/scripts/stop.sh
#   MODE=native deploy/scripts/stop.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MODE="${MODE:-docker}"

if [ "$MODE" = "native" ]; then
    echo ">>> Останавливаю нативный gunicorn…"
    sudo systemctl stop tnoise-web.service
    echo ">>> nginx оставлен запущенным (обслуживает статику/HTTPS)."
    echo "    Полный останов nginx при необходимости: sudo systemctl stop nginx"
else
    echo ">>> Останавливаю docker-стек (тома с данными сохраняются)…"
    export PROJECT_ROOT
    docker compose \
        -f "$PROJECT_ROOT/deploy/docker/docker-compose.prod.yml" \
        --env-file "$PROJECT_ROOT/.env" \
        down
fi
echo ">>> Останов завершён."
