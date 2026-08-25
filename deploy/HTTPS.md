# Перевод прода на HTTPS (Let's Encrypt)

## Состояние на 2026-08-25

Проверено на боевом хосте:

| Проверка | Результат |
|----------|-----------|
| `tnoise.com` A-запись | `159.195.156.249` ✅ (NS — beget) |
| `www.tnoise.com` A-запись | `159.195.156.249` ✅ |
| `http://tnoise.com/`, `http://www.tnoise.com/` | 200, отдаёт patient-app ✅ |
| `http://tnoise.com/api/docs` | 200 ✅ |
| **:443 на хосте** | **свободен** — снаружи `connection refused`, в `ss -tln` слушателя нет ✅ |
| x-ui (раньше занимал 443) | переехал на 2053 / 2096 / 11111 |
| `DJANGO_ALLOWED_HOSTS` | уже содержит `tnoise.com,www.tnoise.com` ✅ |
| `CSRF_TRUSTED_ORIGINS` | уже содержит `https://tnoise.com,https://www.tnoise.com` ✅ |

То есть блокер из предыдущего деплоя (занятый 443) снят — переходить можно.

**Отдельный аргумент за переход:** Android-флейвор `prod` уже собирается с
`API_BASE_URL = "https://tnoise.com/api"` (`patient_app/android/app/build.gradle:67`),
а cleartext-трафик в release-сборке запрещён. Пока на сервере нет HTTPS,
прод-APK физически не может достучаться до бэкенда. HTTPS его чинит.

## Что было не так с прежней схемой

В стеке уже лежали и `nginx.prod.conf` с TLS, и сервис `certbot`, но заработать
это не могло:

1. **Курица и яйцо.** `:443`-блок ссылается на серты, которых на чистом хосте нет,
   → nginx не стартует → challenge отдавать некому → серт не выпустить.
   Обходилось руками через второй конфиг и оверрайд.
2. **Продления не было вообще.** `certbot` сидел под `profiles: ["certbot"]`, то есть
   запускался только вручную. Через 90 дней серт бы истёк и сайт лёг.
3. **Даже после продления nginx отдавал бы старый серт** — он держит файлы
   открытыми до `reload`, а перезагружать было некому.
4. **Bootstrap жил в комментариях**, а не в коде: пять шагов руками, без
   репетиции на staging (у боевого LE — 5 неудачных валидаций на аккаунт в час).

## Внесённые изменения

### `docker-compose.prod.yml`
- `certbot` — из one-shot профиля в **постоянный сайдкар автопродления**:
  цикл `certbot renew --webroot -w /var/www/certbot` каждые 12 ч. Пока сертов нет,
  это безвредный no-op, поэтому сервис можно держать поднятым всегда, в том числе
  в http-режиме.
- `nginx` — добавлен **цикл reload** каждые 6 ч рядом с основным процессом,
  чтобы продлённые серты подхватывались без ручного вмешательства.

### `nginx/nginx.prod.conf`
- **Заглушки `default_server` на :80 и :443** для чужого `Host`. Без них первый
  server-блок становился default-ом, и запрос на `http://159.195.156.249` улетал
  редиректом на `https://159.195.156.249` — адрес, для которого наш серт заведомо
  невалиден. Теперь чужой Host получает `444`, а TLS-handshake рвётся через
  `ssl_reject_handshake` (сертификат не предъявляется вовсе).
  Побочный эффект: **доступ к админке по голому IP перестанет работать** — только
  по домену.
- OCSP stapling **не включаем** (в конфиге лежал закомментированным): Let's Encrypt
  свернул OCSP-респондеры, в свежих сертах нет OCSP URL, и nginx на каждом старте
  писал бы `"ssl_stapling" ignored, no OCSP responder URL`. Проверено локально на
  тестовом серте. Отзыв у LE теперь публикуется через CRL — на стороне nginx
  включать нечего.
- У HSTS уточнён комментарий: после включения браузер запомнит запрет `http://`
  на полгода, откат станет невозможен.

### `scripts/init-letsencrypt.sh` (новый)
Весь bootstrap одной командой, с предполётными проверками:
DNS → :443 свободен → http-стек → **пробный файл в webroot и curl снаружи** →
выпуск серта → `nginx -t` с новыми сертами → переключение стека → проверка https.
Проба webroot до обращения к LE — главное, ради чего скрипт написан: типовые
ошибки (DNS, файрвол, не тот webroot) ловятся, не тратя лимиты Let's Encrypt.
Идемпотентен (`--keep-until-expiring`), есть режим `--staging`.

### `server/config/settings.py`
Добавлен блок `SECURE_HTTPS` (по умолчанию включён при `ENVIRONMENT=prod`):
`SECURE_PROXY_SSL_HEADER`, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`.
Без первого Django считает проксированный запрос небезопасным.
`SECURE_SSL_REDIRECT` намеренно **не** включён: редирект делает nginx, а
healthcheck ходит на `http://127.0.0.1:8000/api/docs` без прокси-заголовков и
получил бы 301 → контейнер стал бы unhealthy.

## Порядок выката

Перед началом — свежий бэкап (см. [BACKUP.md](BACKUP.md)).

```bash
# 0. Доставить изменения на прод (git там нет — только tar/scp)
scp -i pr.key docker-compose.prod.yml deploy@159.195.156.249:~/med_ear_trainig_quiz/
scp -i pr.key nginx/nginx.prod.conf   deploy@159.195.156.249:~/med_ear_trainig_quiz/nginx/
scp -i pr.key scripts/init-letsencrypt.sh deploy@159.195.156.249:~/med_ear_trainig_quiz/scripts/
tar czf - server | ssh -i pr.key deploy@159.195.156.249 'cd ~/med_ear_trainig_quiz && tar xzf -'

ssh -i pr.key deploy@159.195.156.249
cd ~/med_ear_trainig_quiz
chmod +x scripts/init-letsencrypt.sh

# 1. Пересобрать web — код Django запечён в образ
docker compose -f docker-compose.prod.yml -f docker-compose.prod-http.yml up -d --build web

# 2. Репетиция на staging-сервере LE (лимиты не тратятся)
./scripts/init-letsencrypt.sh --staging
#    прошло — удалить staging-серт, как подскажет скрипт:
docker compose -f docker-compose.prod.yml run --rm --entrypoint certbot certbot delete --cert-name tnoise.com

# 3. Боевой выпуск + переключение стека на TLS
./scripts/init-letsencrypt.sh
```

С этого момента **http-оверрайд больше не нужен**, стек поднимается так:

```bash
docker compose -f docker-compose.prod.yml up -d
```

## Проверка после выката

```bash
curl -I https://tnoise.com/                      # 200
curl -I https://www.tnoise.com/                  # 200
curl -I http://tnoise.com/                       # 301 -> https://tnoise.com/
curl -s -o /dev/null -w '%{http_code}\n' https://tnoise.com/api/docs   # 200
curl -I https://tnoise.com/doctors/              # 200
openssl s_client -connect tnoise.com:443 -servername tnoise.com </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -dates        # серт на tnoise.com, +90 дней

# автопродление действительно работает
docker compose -f docker-compose.prod.yml run --rm -T --entrypoint certbot certbot renew --dry-run
docker compose -f docker-compose.prod.yml logs --tail 20 certbot
```

> **`renew --dry-run` «висит» минут пять — это норма, не ломайте его.**
> В non-interactive режиме certbot вставляет случайную задержку до ~8 минут
> («Non-interactive renewal: random delay of N seconds»), чтобы клиенты не
> долбили серверы LE в одну секунду. Ждите, не прерывайте по таймауту.
>
> Если всё-таки прервали: `docker compose run` оставляет контейнер живым, он
> держит lock на `/etc/letsencrypt`, и следующий запуск упадёт с *«Another
> instance of Certbot is already running»*. Лечится так:
> ```bash
> docker ps -aq --filter name=certbot-run | xargs -r docker rm -f
> ```
>
> Сайдкар автопродления этой задержкой не смущается — он живёт в цикле
> с `sleep 12h`. Что он отработал и спит, видно так:
> ```bash
> docker exec med_ear_trainig_quiz-certbot-1 ps -o pid,args   # ждём `sleep 12h`
> ```

Руками: вход в админку `https://tnoise.com/admin/` (проверяет secure-cookie и CSRF)
и вход врача на `https://tnoise.com/doctors/`.

## Откат

Пока HSTS не «прописался» в браузерах — откат простой:

```bash
docker compose -f docker-compose.prod.yml -f docker-compose.prod-http.yml up -d --force-recreate
```

Стек вернётся на `:80` без TLS; серты останутся лежать в томе `letsencrypt` и
пригодятся при следующей попытке.

**После того как HSTS разойдётся по браузерам, откат на HTTP перестанет быть
безболезненным** — клиенты будут сами переписывать `http://` на `https://` ещё
полгода. Если хочется подстраховаться, на первое время уберите строку
`add_header Strict-Transport-Security ...` из `nginx.prod.conf` и верните её,
когда HTTPS отработает пару недель.

## После перехода — что ещё стоит сделать

- Пересобрать и залить прод-APK: теперь `https://tnoise.com/api` наконец отвечает
  (`scripts/build-and-register-apk.sh` с `APK_FLAVOR=prod`).
- Убрать `http://159.195.156.249` из `CSRF_TRUSTED_ORIGINS` в `.env.prod` — по IP
  доступа всё равно не будет.
- Web-бандлы Flutter пересобирать **не нужно**: они ходят на относительный `/api`
  (same-origin), схема подставляется браузером.
