#!/usr/bin/env bash
# Запуск браузерных integration-тестов приложения врача.
#   E2E_HEADLESS=1 (по умолчанию) — headless Chrome.
#   E2E_HEADLESS=0                — обычный (headed) Chrome, нужен дисплей.
# Требуется chromedriver на :4444 (chromedriver --port=4444 &).
#
# Пример:
#   E2E_HEADLESS=0 doctor_app/scripts/run_e2e.sh credentials_e2e_test.dart
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-credentials_e2e_test.dart}"
HEADLESS="${E2E_HEADLESS:-1}"

ARGS=(
  --driver=test_driver/integration_test.dart
  --target="integration_test/${TARGET}"
  -d web-server
  --browser-name=chrome
  --dart-define=FLAVOR=dev
)
if [ "$HEADLESS" = "1" ]; then
  ARGS+=(--headless)
fi

echo "▶ flutter drive (headless=${HEADLESS}) target=${TARGET}"
exec flutter drive "${ARGS[@]}"
