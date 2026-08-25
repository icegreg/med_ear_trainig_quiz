#!/usr/bin/env bash
# Первичный выпуск сертификатов Let's Encrypt и перевод прод-стека на HTTPS.
#
# Запускать НА СЕРВЕРЕ от deploy:
#   ~/med_ear_trainig_quiz/scripts/init-letsencrypt.sh --staging   # репетиция
#   ~/med_ear_trainig_quiz/scripts/init-letsencrypt.sh             # боевой выпуск
#
# Что делает по шагам:
#   1. проверяет, что A-записи доменов смотрят на этот хост и :443 свободен;
#   2. поднимает стек в http-режиме (nginx.prod-http.conf) — он отдаёт
#      /.well-known/acme-challenge/ из тома certbot_www;
#   3. кладёт в webroot пробный файл и проверяет, что он виден снаружи, —
#      это ловит проблемы с DNS/файрволом ДО обращения к Let's Encrypt
#      (у боевого LE жёсткие лимиты на неудачные попытки);
#   4. выпускает серт на tnoise.com + www.tnoise.com (webroot-режим);
#   5. проверяет nginx.prod.conf с новыми сертами (nginx -t) и переключает
#      стек на TLS — БЕЗ http-оверрайда;
#   6. проверяет https и редирект с http.
#
# Идемпотентен: если серт уже есть, шаг 4 пропускается (--keep-until-expiring).
#
# Переменные окружения:
#   LE_DOMAINS  домены через пробел  (по умолчанию "tnoise.com www.tnoise.com")
#   LE_EMAIL    почта для LE         (по умолчанию admin@tnoise.com)
#   STACK_DIR   каталог стека        (по умолчанию ~/med_ear_trainig_quiz)

set -euo pipefail

STACK_DIR="${STACK_DIR:-$HOME/med_ear_trainig_quiz}"
LE_DOMAINS="${LE_DOMAINS:-tnoise.com www.tnoise.com}"
LE_EMAIL="${LE_EMAIL:-admin@tnoise.com}"

STAGING=0
[ "${1:-}" = "--staging" ] && STAGING=1

cd "$STACK_DIR"

PROD=(-f docker-compose.prod.yml)
HTTP=("${PROD[@]}" -f docker-compose.prod-http.yml)
PRIMARY="${LE_DOMAINS%% *}"

log()  { printf '\n\033[1m[le] %s\033[0m\n' "$*"; }
fail() { printf '\n\033[31m[le] ОШИБКА: %s\033[0m\n' "$*" >&2; exit 1; }

# ── 1. Предполётные проверки ──────────────────────────────────────────────
log "1/6 проверяю DNS и порт 443"

MY_IP="$(curl -fsS --max-time 10 https://api.ipify.org || true)"
[ -n "$MY_IP" ] || fail "не удалось определить внешний IP хоста"
echo "     внешний IP хоста: $MY_IP"

for d in $LE_DOMAINS; do
    resolved="$(getent ahostsv4 "$d" | awk '{print $1}' | sort -u | tr '\n' ' ')"
    echo "     $d -> ${resolved:-(не резолвится)}"
    case " $resolved " in
        *" $MY_IP "*) ;;
        *) fail "A-запись $d не указывает на $MY_IP — LE не сможет пройти проверку" ;;
    esac
done

# 443 должен быть свободен: раньше его занимала панель x-ui.
if ss -tln 2>/dev/null | grep -qE '(^|\s)(0\.0\.0\.0|\[::\]|\*):443\s'; then
    ss -tlnp 2>/dev/null | grep ':443' || true
    fail "порт 443 уже занят другим процессом — освободите его перед переходом на TLS"
fi
echo "     :443 свободен"

# ── 2. http-режим ─────────────────────────────────────────────────────────
log "2/6 поднимаю стек в http-режиме (ACME webroot доступен на :80)"
docker compose "${HTTP[@]}" up -d
docker compose "${HTTP[@]}" ps

# ── 3. Проверка webroot снаружи ───────────────────────────────────────────
log "3/6 проверяю, что ACME-challenge виден снаружи"
PROBE="probe-$$"
docker compose "${HTTP[@]}" exec -T nginx sh -c \
    "mkdir -p /var/www/certbot/.well-known/acme-challenge && echo $PROBE > /var/www/certbot/.well-known/acme-challenge/$PROBE"
for d in $LE_DOMAINS; do
    got="$(curl -fsS --max-time 15 "http://$d/.well-known/acme-challenge/$PROBE" || true)"
    [ "$got" = "$PROBE" ] || fail "http://$d/.well-known/acme-challenge/ недоступен снаружи (получено: '${got:-пусто}')"
    echo "     $d — ok"
done
docker compose "${HTTP[@]}" exec -T nginx rm -f "/var/www/certbot/.well-known/acme-challenge/$PROBE"

# ── 4. Выпуск сертификата ─────────────────────────────────────────────────
log "4/6 выпускаю сертификат для: $LE_DOMAINS"
CERT_ARGS=(certonly --webroot -w /var/www/certbot
           --email "$LE_EMAIL" --agree-tos --no-eff-email
           --keep-until-expiring --non-interactive)
for d in $LE_DOMAINS; do CERT_ARGS+=(-d "$d"); done
if [ "$STAGING" = 1 ]; then
    echo "     РЕЖИМ STAGING: серт будет невалидным для браузера, но лимиты LE не тратятся"
    CERT_ARGS+=(--staging)
fi

docker compose "${PROD[@]}" run --rm --entrypoint certbot certbot "${CERT_ARGS[@]}"

if [ "$STAGING" = 1 ]; then
    log "staging-репетиция прошла. Теперь удалите staging-серт и запустите без --staging:"
    echo "     docker compose ${PROD[*]} run --rm --entrypoint certbot certbot delete --cert-name $PRIMARY"
    echo "     $0"
    exit 0
fi

# ── 5. Переключение на TLS ────────────────────────────────────────────────
log "5/6 проверяю nginx.prod.conf с новыми сертами и переключаю стек на TLS"
# Проверяем ИМЕННО через compose: в отдельном `docker run` контейнер не в сети
# проекта, upstream `web:8000` не резолвится и nginx -t падает на ровном месте.
# --no-deps — web и db уже подняты, поднимать их заново не нужно.
docker compose "${PROD[@]}" run --rm --no-deps --entrypoint nginx nginx -t \
    || fail "nginx -t не прошёл, стек остаётся на http"

# Пересоздаём nginx уже по базовому файлу (порты и конфиг меняются, поэтому
# --force-recreate: иначе compose оставит контейнер со старым набором портов).
docker compose "${PROD[@]}" up -d --force-recreate --remove-orphans

# ── 6. Проверка ───────────────────────────────────────────────────────────
log "6/6 проверяю результат"
sleep 5
for d in $LE_DOMAINS; do
    printf '     https://%s/          ' "$d"
    curl -s -o /dev/null -w 'HTTP %{http_code}, cert ok\n' --max-time 15 "https://$d/" \
        || echo "НЕ ОТВЕЧАЕТ"
    printf '     http://%s/  редирект ' "$d"
    curl -s -o /dev/null -w '%{http_code} -> %{redirect_url}\n' --max-time 15 "http://$d/"
done
printf '     https://%s/api/docs   ' "$PRIMARY"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 15 "https://$PRIMARY/api/docs"

log "готово. Дальше стек поднимается БЕЗ http-оверрайда:"
echo "     docker compose -f docker-compose.prod.yml up -d"
echo
echo "Продление автоматическое (сайдкар certbot + reload nginx), проверить:"
echo "     docker compose -f docker-compose.prod.yml logs certbot"
echo "     docker compose -f docker-compose.prod.yml run --rm --entrypoint certbot certbot renew --dry-run"
