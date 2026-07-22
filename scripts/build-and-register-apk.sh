#!/usr/bin/env bash
# Собрать пациентский APK в Docker и сразу зарегистрировать его в реестре релизов.
# Kaiten #67652021.
#
# Шаг 1: сборка во Flutter-контейнере (apk-build) — кладёт tnoise-*.apk
#        в media/releases/incoming/ (том media_data, общий с web).
# Шаг 2: регистрация в контейнере web (там Django + PostgreSQL) — версия берётся
#        из имени файла командой register_incoming.
#
# Два контейнера потому, что БД доступна только web, а Flutter — только apk-build.
#
# Использование:
#   scripts/build-and-register-apk.sh                 # preprod, дефолт, cleanup
#   APK_FLAVOR=prod scripts/build-and-register-apk.sh # prod
#   SET_DEFAULT=0 scripts/build-and-register-apk.sh   # не делать дефолтным
set -euo pipefail

cd "$(dirname "$0")/.."

APK_FLAVOR="${APK_FLAVOR:-preprod}"
# preprod по умолчанию делаем дефолтным (удобно для стенда); отключается SET_DEFAULT=0.
SET_DEFAULT="${SET_DEFAULT:-1}"

echo "==> [1/2] Сборка APK (flavor=$APK_FLAVOR)"
APK_FLAVOR="$APK_FLAVOR" docker compose --profile build run --rm apk-build

echo "==> [2/2] Регистрация в реестре релизов"
args=(--flavor "$APK_FLAVOR" --cleanup)
if [ "$SET_DEFAULT" = "1" ]; then
    args+=(--set-default)
fi
docker compose exec -T web python manage.py register_incoming "${args[@]}"

echo "==> Готово. Проверить: админка «Релизы APK» или GET /api/releases/latest"
