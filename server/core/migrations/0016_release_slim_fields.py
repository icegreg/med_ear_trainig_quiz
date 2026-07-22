"""Убрать из Release поля, не нужные для раздачи на скачивание (Kaiten #67689761).

Удаляются version_code, commit_sha, notes, file_size. Уникальность релиза
переносится с (version_name, version_code) на version_name.

versionCode остаётся в самом APK (Android-поле манифеста) — убирается только из
реестра. Размер теперь выводится из файла (property Release.file_size).

Порядок: сначала снять старый unique-констрейнт (он ссылается на version_code),
затем удалить поля, затем добавить новый констрейнт по version_name.
"""
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0015_alter_quizquestion_correct_answer'),
    ]

    operations = [
        migrations.RemoveConstraint(
            model_name='release',
            name='uniq_release_version',
        ),
        migrations.RemoveField(model_name='release', name='version_code'),
        migrations.RemoveField(model_name='release', name='commit_sha'),
        migrations.RemoveField(model_name='release', name='notes'),
        migrations.RemoveField(model_name='release', name='file_size'),
        migrations.AddConstraint(
            model_name='release',
            constraint=models.UniqueConstraint(
                fields=['version_name'], name='uniq_release_version'
            ),
        ),
    ]
