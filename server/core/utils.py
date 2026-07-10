"""Утилиты: транслитерация ФИО и генерация свободного логина пациента."""
from __future__ import annotations

import re

from django.contrib.auth.models import User

# Простая фонетическая транслитерация кириллицы в латиницу (нижний регистр).
_TRANSLIT = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e',
    'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
    'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
    'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
    'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
    # украинские/белорусские на всякий случай
    'і': 'i', 'ї': 'i', 'є': 'ye', 'ґ': 'g', 'ў': 'u',
}


def get_client_ip(request) -> str:
    """IP клиента с учётом X-Forwarded-For (за nginx/прокси)."""
    xff = request.META.get('HTTP_X_FORWARDED_FOR')
    if xff:
        return xff.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR', 'unknown')


def transliterate(text: str) -> str:
    """Кириллица → латиница (нижний регистр), прочие символы отбрасываются."""
    if not text:
        return ''
    out = []
    for ch in text.lower():
        if ch in _TRANSLIT:
            out.append(_TRANSLIT[ch])
        elif ch.isascii() and ch.isalnum():
            out.append(ch)
        # всё остальное (пробелы, дефисы, апострофы) пропускаем
    return ''.join(out)


def _sanitize(login: str) -> str:
    """Оставляем только [a-z0-9]."""
    return re.sub(r'[^a-z0-9]', '', login.lower())


def build_login_base(
    last_name: str,
    first_name: str = '',
    patronymic: str = '',
    clinic_abbr: str = '',
) -> str:
    """Базовый логин: транслит фамилии + инициалы имени и отчества.

    «Иванов Пётр Сергеевич» → ``ivanovps``; «Иванова Анна» → ``ivanovaa``.

    Если задана аббревиатура клиники, она добавляется префиксом через дефис:
    ``msk-ivanovps`` (по типу аэропортов, в нижнем регистре).
    """
    last = transliterate(last_name)
    first_initial = transliterate(first_name[:1]) if first_name else ''
    patr_initial = transliterate(patronymic[:1]) if patronymic else ''
    name_part = _sanitize(last + first_initial + patr_initial) or 'patient'
    prefix = _sanitize(clinic_abbr)
    if prefix:
        return f'{prefix}-{name_part}'
    return name_part


def _username_taken(username: str) -> bool:
    return User.objects.filter(username=username).exists()


def generate_patient_login(
    last_name: str,
    first_name: str = '',
    patronymic: str = '',
    birth_date=None,
    clinic_abbr: str = '',
    *,
    max_increment: int = 1000,
) -> str:
    """Свободный логин по ФИО.

    С аббревиатурой клиники: ``base`` → ``base2``, ``base3``, … где
    ``base`` = ``abbr-фамилияинициалы`` (порядковый номер только при дубликате).

    Без клиники (легаси-путь): ``base`` → ``base`` + 2 цифры года рождения →
    ``base2``, ``base3``, … пока не найдётся незанятый.
    """
    base = build_login_base(last_name, first_name, patronymic, clinic_abbr)

    if not _username_taken(base):
        return base

    # Год рождения как суффикс — только для легаси-логинов без клиники.
    if not _sanitize(clinic_abbr) and birth_date is not None:
        year_suffix = f'{birth_date.year % 100:02d}'
        candidate = f'{base}{year_suffix}'
        if not _username_taken(candidate):
            return candidate

    for n in range(2, max_increment + 1):
        candidate = f'{base}{n}'
        if not _username_taken(candidate):
            return candidate

    # Практически недостижимо; финальный fallback.
    raise RuntimeError('Не удалось подобрать свободный логин.')
