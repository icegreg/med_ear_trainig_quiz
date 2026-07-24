#!/usr/bin/env bash
# Старт прод-стека TNOISE.
#
#   MODE=docker  (по умолчанию) — поднять docker-compose.prod.yml.
#   MODE=native               — запустить systemd-юниты (gunicorn + nginx).
#
# Примеры:
#   deploy/scripts/start.sh
#   MODE=native deploy/scripts/start.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MODE="${MODE:-docker}"

if [ "$MODE" = "native" ]; then
    echo ">>> Запускаю нативные сервисы (systemd)…"
    sudo systemctl start tnoise-web.service
    sudo systemctl reload-or-restart nginx
    sudo systemctl --no-pager status tnoise-web.service | head -n 5
else
    echo ">>> Поднимаю docker-стек…"
    export PROJECT_ROOT
    docker compose \
        -f "$PROJECT_ROOT/deploy/docker/docker-compose.prod.yml" \
        --env-file "$PROJECT_ROOT/.env" \
        up -d --build
    docker compose \
        -f "$PROJECT_ROOT/deploy/docker/docker-compose.prod.yml" \
        --env-file "$PROJECT_ROOT/.env" ps
fi
echo ">>> Старт завершён."
