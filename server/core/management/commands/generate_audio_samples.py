"""
Генерация реальных WAV-файлов: ноты и аккорды.
Создаёт AudioFile записи в БД и файлы на диске.

Примеры:
  python manage.py generate_audio_samples
  python manage.py generate_audio_samples --replace  # заменить существующие
"""

import math
import os
import struct
import wave

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand

from core.models import AudioFile

# Частоты нот (4-я октава)
NOTES = {
    'C4': 261.63,
    'D4': 293.66,
    'E4': 329.63,
    'F4': 349.23,
    'G4': 392.00,
    'A4': 440.00,
    'B4': 493.88,
    'C5': 523.25,
}

# Аккорды — комбинации нот
CHORDS = {
    'C-мажор': ['C4', 'E4', 'G4'],
    'D-минор': ['D4', 'F4', 'A4'],
    'E-минор': ['E4', 'G4', 'B4'],
    'F-мажор': ['F4', 'A4', 'C5'],
    'G-мажор': ['G4', 'B4', 'D4'],
    'A-минор': ['A4', 'C5', 'E4'],
}

SAMPLE_RATE = 44100
DURATION = 2.0  # секунды
AMPLITUDE = 0.5


def generate_tone(frequencies, duration=DURATION, sample_rate=SAMPLE_RATE):
    """Генерирует PCM-данные для одной или нескольких частот (аккорд)."""
    n_samples = int(sample_rate * duration)
    samples = []
    for i in range(n_samples):
        t = i / sample_rate
        # Сумма синусоид
        value = sum(math.sin(2 * math.pi * f * t) for f in frequencies)
        # Нормализация
        value = value / len(frequencies) * AMPLITUDE

        # Fade in/out (50ms) чтобы убрать щелчки
        fade_samples = int(0.05 * sample_rate)
        if i < fade_samples:
            value *= i / fade_samples
        elif i > n_samples - fade_samples:
            value *= (n_samples - i) / fade_samples

        # 16-bit PCM
        sample = int(value * 32767)
        sample = max(-32768, min(32767, sample))
        samples.append(struct.pack('<h', sample))

    return b''.join(samples)


def create_wav(pcm_data, sample_rate=SAMPLE_RATE):
    """Оборачивает PCM-данные в WAV-формат (в памяти)."""
    import io
    buf = io.BytesIO()
    with wave.open(buf, 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm_data)
    return buf.getvalue()


class Command(BaseCommand):
    help = 'Генерация реальных WAV-файлов: ноты и аккорды'

    def add_arguments(self, parser):
        parser.add_argument(
            '--replace', action='store_true',
            help='Удалить существующие аудио-файлы и заменить новыми',
        )

    def handle(self, *args, **options):
        if options['replace']:
            count = AudioFile.all_objects.count()
            if count:
                AudioFile.all_objects.all().hard_delete()
                self.stdout.write(self.style.WARNING(
                    f'Удалено {count} существующих аудио-файлов'
                ))

        created = 0

        # Ноты
        self.stdout.write(self.style.MIGRATE_HEADING('Генерация нот...'))
        for name, freq in NOTES.items():
            title = f'Нота {name}'
            if AudioFile.all_objects.filter(title=title).exists():
                self.stdout.write(f'  {title} — уже существует, пропуск')
                continue

            pcm = generate_tone([freq])
            wav_data = create_wav(pcm)

            af = AudioFile(
                title=title,
                duration_seconds=int(DURATION),
            )
            af.file.save(
                f'note_{name.lower()}.wav',
                ContentFile(wav_data),
                save=True,
            )
            created += 1
            self.stdout.write(f'  {title} ({freq} Hz) — создан')

        # Аккорды
        self.stdout.write(self.style.MIGRATE_HEADING('Генерация аккордов...'))
        for chord_name, note_names in CHORDS.items():
            title = f'Аккорд {chord_name}'
            if AudioFile.all_objects.filter(title=title).exists():
                self.stdout.write(f'  {title} — уже существует, пропуск')
                continue

            frequencies = [NOTES[n] for n in note_names]
            pcm = generate_tone(frequencies)
            wav_data = create_wav(pcm)

            slug = chord_name.lower().replace('-', '_').replace(' ', '_')
            af = AudioFile(
                title=title,
                duration_seconds=int(DURATION),
            )
            af.file.save(
                f'chord_{slug}.wav',
                ContentFile(wav_data),
                save=True,
            )
            created += 1
            notes_str = ' + '.join(note_names)
            self.stdout.write(f'  {title} ({notes_str}) — создан')

        self.stdout.write(self.style.SUCCESS(
            f'\nГотово: создано {created} аудио-файлов '
            f'(всего в БД: {AudioFile.objects.count()})'
        ))
