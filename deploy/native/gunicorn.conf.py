"""Конфиг gunicorn для нативной установки TNOISE.

Запускается systemd-юнитом tnoise-web.service. Слушает только localhost —
наружу трафик выпускает nginx (TLS + раздача статики/Flutter web).
"""

bind = "127.0.0.1:8000"
workers = 3
timeout = 60
graceful_timeout = 30
keepalive = 5

# Логи в journald (systemd подхватит stdout/stderr).
accesslog = "-"
errorlog = "-"
loglevel = "info"
