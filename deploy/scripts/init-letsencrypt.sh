#!/usr/bin/env bash
# Первичный выпуск сертификата Let's Encrypt для Docker-стека TNOISE.
#
# Решает проблему «курицы и яйца»: nginx не стартует без сертификата, а
# сертификат нельзя получить без работающего nginx на :80. Порядок:
#   1) кладём временный self-signed сертификат, чтобы nginx поднялся;
#   2) поднимаем nginx;
#   3) удаляем заглушку и запрашиваем настоящий сертификат по webroot;
#   4) перезагружаем nginx.
#
# Запускать ОДИН РАЗ при первичной установке. Продление потом автоматическое
# (сервис certbot в docker-compose.prod.yml). DNS tnoise.com уже должен
# указывать на этот сервер.
#
# Использование:  deploy/scripts/init-letsencrypt.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE="docker compose -f $PROJECT_ROOT/deploy/docker/docker-compose.prod.yml --env-file $PROJECT_ROOT/.env"
export PROJECT_ROOT

# shellcheck disable=SC1091
set -a; . "$PROJECT_ROOT/.env"; set +a

DOMAINS="${CERTBOT_DOMAINS:-tnoise.com www.tnoise.com}"
EMAIL="${CERTBOT_EMAIL:-admin@tnoise.com}"
PRIMARY="${DOMAINS%% *}"          # первый домен = имя каталога live/
STAGING="${CERTBOT_STAGING:-0}"   # 1 = тестовый сервер LE (не тратит лимиты)

echo ">>> Домены: $DOMAINS  (primary: $PRIMARY),  email: $EMAIL"

# 1. Временный self-signed сертификат.
echo ">>> Кладу временный self-signed сертификат…"
$COMPOSE run --rm --entrypoint "\
  sh -c 'mkdir -p /etc/letsencrypt/live/$PRIMARY && \
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
      -keyout /etc/letsencrypt/live/$PRIMARY/privkey.pem \
      -out /etc/letsencrypt/live/$PRIMARY/fullchain.pem \
      -subj /CN=$PRIMARY'" certbot

# 2. Поднимаем nginx (и web/db как зависимости).
echo ">>> Поднимаю nginx…"
$COMPOSE up -d nginx
sleep 5

# 3. Удаляем заглушку и запрашиваем настоящий сертификат.
echo ">>> Удаляю заглушку и запрашиваю сертификат Let's Encrypt…"
$COMPOSE run --rm --entrypoint "\
  rm -rf /etc/letsencrypt/live/$PRIMARY \
         /etc/letsencrypt/archive/$PRIMARY \
         /etc/letsencrypt/renewal/$PRIMARY.conf" certbot

domain_args=""
for d in $DOMAINS; do domain_args="$domain_args -d $d"; done
staging_arg=""; [ "$STAGING" != "0" ] && staging_arg="--staging"

# shellcheck disable=SC2086
$COMPOSE run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg $domain_args \
    --email $EMAIL --agree-tos --no-eff-email --non-interactive --force-renewal" certbot

# 4. Перезагружаем nginx с настоящим сертификатом.
echo ">>> Перезагружаю nginx…"
$COMPOSE exec nginx nginx -s reload

echo ">>> Готово. HTTPS для $PRIMARY выпущен."
echo ">>> Дальше поднимите весь стек: deploy/scripts/start.sh"
