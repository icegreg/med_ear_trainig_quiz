"""Сигналы приложения core.

Держим стабильный `latest.apk` в синхроне с дефолтным релизом при любом пути
изменения (форма админки, action, удаление) — Kaiten #67702702.
"""
from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from .models import Release


@receiver(post_save, sender=Release)
@receiver(post_delete, sender=Release)
def sync_latest_apk(sender, **kwargs):
    Release.refresh_latest()
