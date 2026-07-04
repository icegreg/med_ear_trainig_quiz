"""Лог действий врача (аудит): назначение/снятие/просмотр тестов, сброс пароля.

Хранение — один .jsonl-файл на врача, по одной JSON-записи в строке
(по аналогии с core.client_logs). Пароли в лог не пишутся.
"""
import fcntl
import json
from datetime import datetime, timezone
from pathlib import Path

from django.conf import settings

# Человекочитаемые названия действий.
ACTION_LABELS = {
    'assign_quiz': 'Назначен тест',
    'unassign_quiz': 'Снято назначение',
    'review_results': 'Просмотрены результаты',
    'reset_password': 'Сброс пароля пациента',
}


def log_path(doctor_id) -> Path:
    """Путь к .jsonl-файлу лога действий врача."""
    return Path(settings.CLIENT_LOGS_DIR) / f'doctor_{doctor_id}.jsonl'


def append_action(doctor_id, action, *, patient=None, detail='', ip=None) -> None:
    """Записать одно действие врача. Пароль сюда никогда не передаётся."""
    path = log_path(doctor_id)
    path.parent.mkdir(parents=True, exist_ok=True)

    entry = {
        'ts': datetime.now(timezone.utc).isoformat(),
        'action': action,
        'action_label': ACTION_LABELS.get(action, action),
        'patient_id': getattr(patient, 'id', None),
        'patient': str(patient) if patient is not None else None,
        'detail': detail,
        'ip': ip,
    }
    with path.open('a', encoding='utf-8') as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        try:
            f.write(json.dumps(entry, ensure_ascii=False, default=str) + '\n')
        finally:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)


def read_tail(doctor_id, max_lines: int = 500) -> list[str]:
    """Последние max_lines строк лога. Если файла нет — []."""
    path = log_path(doctor_id)
    if not path.exists():
        return []
    with path.open('r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()
    return [ln.rstrip('\n') for ln in lines[-max_lines:]]


def file_size(doctor_id) -> int:
    """Размер файла лога в байтах (0 если нет)."""
    path = log_path(doctor_id)
    return path.stat().st_size if path.exists() else 0


def line_count(doctor_id) -> int:
    """Сколько строк в файле лога (0 если нет)."""
    path = log_path(doctor_id)
    if not path.exists():
        return 0
    with path.open('rb') as f:
        return sum(1 for _ in f)
