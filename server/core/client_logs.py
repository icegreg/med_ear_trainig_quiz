"""Запись и чтение клиентских логов пациента.

Хранение — один .jsonl-файл на пациента, по одной JSON-записи в строке.
Концурентная запись защищена fcntl.flock (Linux/macOS).
"""
import fcntl
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from django.conf import settings


def log_path(patient_id: int) -> Path:
    """Путь к .jsonl-файлу клиентских логов пациента."""
    return Path(settings.CLIENT_LOGS_DIR) / f'patient_{patient_id}.jsonl'


def append_entries(patient_id: int, entries: Iterable[dict]) -> int:
    """Дописывает записи в файл пациента. Возвращает количество записанных строк.

    Каждая запись дополняется server_received_at — время приёма сервером.
    """
    path = log_path(patient_id)
    path.parent.mkdir(parents=True, exist_ok=True)

    received_at = datetime.now(timezone.utc).isoformat()
    count = 0
    with path.open('a', encoding='utf-8') as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        try:
            for entry in entries:
                line = {**entry, 'server_received_at': received_at}
                f.write(json.dumps(line, ensure_ascii=False, default=str) + '\n')
                count += 1
        finally:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    return count


def read_tail(patient_id: int, max_lines: int = 500) -> list[str]:
    """Возвращает последние max_lines строк лога. Если файла нет — []."""
    path = log_path(patient_id)
    if not path.exists():
        return []
    with path.open('r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()
    return [ln.rstrip('\n') for ln in lines[-max_lines:]]


def file_size(patient_id: int) -> int:
    """Размер файла логов в байтах (0 если нет)."""
    path = log_path(patient_id)
    return path.stat().st_size if path.exists() else 0


def line_count(patient_id: int) -> int:
    """Сколько строк в файле логов (0 если нет)."""
    path = log_path(patient_id)
    if not path.exists():
        return 0
    with path.open('rb') as f:
        return sum(1 for _ in f)
