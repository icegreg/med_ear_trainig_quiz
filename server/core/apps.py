from django.apps import AppConfig


class CoreConfig(AppConfig):
    name = 'core'

    def ready(self):
        # Регистрируем сигналы (синхронизация latest.apk с дефолтом).
        from . import signals  # noqa: F401
