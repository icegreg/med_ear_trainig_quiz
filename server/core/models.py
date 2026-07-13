import os
import secrets
import shutil
import uuid
from datetime import timedelta

from django.conf import settings
from django.db import models, transaction
from django.utils import timezone

# Срок жизни device token — 3 месяца.
DEVICE_TOKEN_LIFETIME = timedelta(days=90)


def default_token_expiry():
    return timezone.now() + DEVICE_TOKEN_LIFETIME


class SoftDeleteQuerySet(models.QuerySet):
    def alive(self):
        return self.filter(deleted_at__isnull=True)

    def deleted(self):
        return self.filter(deleted_at__isnull=False)

    def delete(self):
        """Массовый soft delete (используется в админке)."""
        return self.update(deleted_at=timezone.now())

    def hard_delete(self):
        """Физическое удаление."""
        return super().delete()


class SoftDeleteManager(models.Manager):
    """Менеджер, по умолчанию возвращающий только неудалённые записи."""

    def get_queryset(self):
        return SoftDeleteQuerySet(self.model, using=self._db).alive()


class SoftDeleteAllManager(models.Manager):
    """Менеджер, возвращающий все записи включая удалённые."""

    def get_queryset(self):
        return SoftDeleteQuerySet(self.model, using=self._db)


class SoftDeleteMixin(models.Model):
    """Миксин soft delete: deleted_at + deleted_by."""
    deleted_at = models.DateTimeField(
        'Дата удаления', null=True, blank=True, db_index=True,
    )
    deleted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='+',
        verbose_name='Кем удалено',
    )

    objects = SoftDeleteManager()
    all_objects = SoftDeleteAllManager()

    class Meta:
        abstract = True

    @property
    def is_deleted(self):
        return self.deleted_at is not None

    def delete(self, using=None, keep_parents=False, user=None):
        """Soft delete — маркировка."""
        self.deleted_at = timezone.now()
        self.deleted_by = user
        self.save(update_fields=['deleted_at', 'deleted_by'])

    def hard_delete(self, using=None, keep_parents=False):
        """Физическое удаление из БД."""
        super().delete(using=using, keep_parents=keep_parents)

    def restore(self):
        """Восстановление удалённой записи."""
        self.deleted_at = None
        self.deleted_by = None
        self.save(update_fields=['deleted_at', 'deleted_by'])


class Doctor(models.Model):
    """Профиль врача. Регистрация только через админку."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='doctor_profile',
    )
    last_name = models.CharField('Фамилия', max_length=150)
    first_name = models.CharField('Имя', max_length=150)
    patronymic = models.CharField('Отчество', max_length=150, blank=True)
    clinic = models.CharField('Клиника', max_length=255, blank=True)
    logging_enabled = models.BooleanField(
        'Логирование клиента',
        default=False,
        help_text='Если включено, все пациенты этого врача отправляют клиентские логи на сервер',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'Врач'
        verbose_name_plural = 'Врачи'

    def __str__(self):
        parts = [self.last_name, self.first_name]
        if self.patronymic:
            parts.append(self.patronymic)
        return ' '.join(parts)


class Clinic(models.Model):
    """Клиника (медцентр). К клинике привязываются пациенты."""
    name = models.CharField('Название', max_length=255)
    address = models.CharField('Адрес', max_length=500, blank=True)
    abbreviation = models.CharField(
        'Аббревиатура', max_length=10, unique=True,
        help_text='Короткая латинская аббревиатура (по типу аэропортов), '
                  'например MSK. Используется как префикс логина пациента.',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'Клиника'
        verbose_name_plural = 'Клиники'
        ordering = ['name']

    def __str__(self):
        return f'{self.name} ({self.abbreviation})'


class Patient(models.Model):
    """Профиль пациента, привязан к пользователю Django и врачу."""
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='patient_profile',
    )
    doctor = models.ForeignKey(
        Doctor,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='patients',
    )
    clinic = models.ForeignKey(
        'Clinic',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='patients',
        verbose_name='Клиника',
    )
    starting_sound = models.ForeignKey(
        'AudioFile',
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='starting_sound_patients',
        verbose_name='Стартовый звук',
        help_text='Звук, воспроизводимый перед каждым тестом пациента',
    )
    last_name = models.CharField('Фамилия', max_length=150, blank=True)
    first_name = models.CharField('Имя', max_length=150, blank=True)
    patronymic = models.CharField('Отчество', max_length=150, blank=True)
    birth_date = models.DateField('Дата рождения', null=True, blank=True)
    logging_enabled = models.BooleanField(
        'Логирование клиента',
        default=False,
        help_text='Если включено, приложение пациента отправляет логи всех запросов на сервер',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'Пациент'
        verbose_name_plural = 'Пациенты'
        ordering = ['last_name', 'first_name']

    def __str__(self):
        fio = self.full_name
        return fio if fio else f'Пациент {self.user.username}'

    @property
    def full_name(self) -> str:
        parts = [p for p in [self.last_name, self.first_name, self.patronymic] if p]
        return ' '.join(parts)

    @property
    def effective_logging_enabled(self) -> bool:
        """Логирование считается включённым, если включено у самого пациента
        ИЛИ у его врача (массово)."""
        if self.logging_enabled:
            return True
        return bool(self.doctor and self.doctor.logging_enabled)


class AudioCategory(models.Model):
    """Категория (папка) аудио-файлов. Поддерживает иерархию."""
    name = models.CharField('Название', max_length=255)
    parent = models.ForeignKey(
        'self',
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='children',
        verbose_name='Родительская категория',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'Категория аудио'
        verbose_name_plural = 'Категории аудио'
        ordering = ['name']

    def __str__(self):
        parts = [self.name]
        parent = self.parent
        depth = 0
        while parent and depth < 10:
            parts.insert(0, parent.name)
            parent = parent.parent
            depth += 1
        return ' / '.join(parts)

    @classmethod
    def get_default(cls):
        """Возвращает (или создаёт) корневую категорию «Общая»."""
        cat, _ = cls.objects.get_or_create(name='Общая', parent=None)
        return cat


class AudioFile(SoftDeleteMixin):
    """Аудио-файл, хранится на сервере. Удаление через маркировку."""
    title = models.CharField(max_length=255)
    file = models.FileField(upload_to='audio/')
    category = models.ForeignKey(
        AudioCategory,
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='audio_files',
        verbose_name='Категория',
    )
    duration_seconds = models.PositiveIntegerField(
        null=True, blank=True, help_text='Длительность в секундах'
    )
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'Аудио-файл'
        verbose_name_plural = 'Аудио-файлы'

    def __str__(self):
        prefix = '[УДАЛЁН] ' if self.is_deleted else ''
        return f'{prefix}{self.title}'

    def save(self, *args, **kwargs):
        if not self.category_id:
            self.category = AudioCategory.get_default()
        super().save(*args, **kwargs)

    def hard_delete(self, using=None, keep_parents=False):
        """Физическое удаление — файл с диска + запись из БД."""
        if self.file:
            self.file.delete(save=False)
        super().hard_delete(using=using, keep_parents=keep_parents)


class Quiz(models.Model):
    """Тест (квиз) — набор вопросов с аудио."""
    title = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    audio_files = models.ManyToManyField(
        AudioFile, blank=True, related_name='quizzes'
    )
    created_by = models.ForeignKey(
        'Doctor',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='created_quizzes',
        verbose_name='Создан врачом',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Квиз'
        verbose_name_plural = 'Квизы'

    def __str__(self):
        return self.title


class Answer(models.TextChoices):
    """Ответ на вопрос теста. Хранится как «да»/«нет» — так его пишет
    пациентское приложение в неизменяемый QuizResult.answers; «Слышу» /
    «Не слышу» — это только подпись в интерфейсе.
    """
    YES = 'да', 'Слышу'
    NO = 'нет', 'Не слышу'


def default_question_options():
    return [Answer.YES.value, Answer.NO.value]


class QuizQuestion(models.Model):
    """Вопрос в квизе, привязан к аудио-файлу."""
    Answer = Answer

    quiz = models.ForeignKey(Quiz, on_delete=models.CASCADE, related_name='questions')
    audio_file = models.ForeignKey(
        AudioFile, on_delete=models.SET_NULL, null=True, related_name='questions'
    )
    text = models.TextField(help_text='Текст вопроса')
    options = models.JSONField(
        default=default_question_options,
        help_text='Варианты ответов, например: ["да", "нет"]',
    )
    # Тест на слух: почти всегда звук должен быть услышан, поэтому «слышу» —
    # дефолт, а не то, что каждый раз вбивают руками.
    correct_answer = models.CharField(
        max_length=255,
        choices=Answer.choices,
        default=Answer.YES,
    )
    order = models.PositiveIntegerField(default=0)

    class Meta:
        verbose_name = 'Вопрос'
        verbose_name_plural = 'Вопросы'
        ordering = ['order']

    def __str__(self):
        return f'Вопрос {self.order} — {self.quiz.title}'


class PatientQuizAssignment(models.Model):
    """Назначение квиза пациенту."""

    class Status(models.TextChoices):
        ASSIGNED = 'assigned', 'Назначен'
        COMPLETED = 'completed', 'Пройден'

    patient = models.ForeignKey(
        Patient, on_delete=models.CASCADE, related_name='quiz_assignments'
    )
    quiz = models.ForeignKey(
        Quiz, on_delete=models.CASCADE, related_name='assignments'
    )
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.ASSIGNED
    )
    assigned_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    starts_at = models.DateTimeField(
        'Начало доступа', null=True, blank=True,
        help_text='Когда тест становится доступен. null = сразу.',
    )
    ends_at = models.DateTimeField(
        'Крайний срок', null=True, blank=True,
        help_text='Когда тест перестаёт быть доступен. null = бессрочно.',
    )
    reviewed_at = models.DateTimeField(
        'Просмотрено врачом', null=True, blank=True,
        help_text='Когда врач впервые открыл результат. null = не просмотрен.',
    )

    class Meta:
        verbose_name = 'Назначение квиза'
        verbose_name_plural = 'Назначения квизов'
        unique_together = ['patient', 'quiz']

    def __str__(self):
        return f'{self.patient} — {self.quiz} ({self.get_status_display()})'

    @property
    def is_available(self):
        """Доступен ли тест для прохождения прямо сейчас."""
        if self.status == self.Status.COMPLETED:
            return False
        now = timezone.now()
        if self.starts_at and now < self.starts_at:
            return False
        if self.ends_at and now > self.ends_at:
            return False
        return True

    @property
    def is_upcoming(self):
        """Тест назначен, но ещё не наступил starts_at."""
        if self.status == self.Status.COMPLETED:
            return False
        if self.starts_at and timezone.now() < self.starts_at:
            return True
        return False

    @property
    def is_expired(self):
        """Срок прохождения истёк."""
        if self.status == self.Status.COMPLETED:
            return False
        if self.ends_at and timezone.now() > self.ends_at:
            return True
        return False

    @property
    def days_until_deadline(self):
        """Кол-во дней до дедлайна. None если бессрочно или завершён."""
        if not self.ends_at or self.status == self.Status.COMPLETED:
            return None
        delta = self.ends_at - timezone.now()
        return max(0, delta.days)


class QuizResult(SoftDeleteMixin):
    """Результат прохождения квиза. Удаление через маркировку."""
    assignment = models.OneToOneField(
        PatientQuizAssignment, on_delete=models.CASCADE, related_name='result'
    )
    answers = models.JSONField(
        help_text='Ответы пациента: [{"question_id": 1, "answer": "A"}, ...]'
    )
    score = models.PositiveIntegerField(null=True, blank=True)
    submitted_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'Результат теста'
        verbose_name_plural = 'Результаты тестов'

    def __str__(self):
        prefix = '[УДАЛЁН] ' if self.is_deleted else ''
        return f'{prefix}Результат: {self.assignment}'


class DeviceToken(models.Model):
    """Долгоживущий токен устройства пациента."""
    token = models.CharField(
        max_length=64, unique=True, db_index=True,
        default=secrets.token_hex,
    )
    patient = models.ForeignKey(
        Patient, on_delete=models.CASCADE, related_name='device_tokens'
    )
    device_info = models.CharField(max_length=255, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(default=default_token_expiry)
    last_used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = 'Токен устройства'
        verbose_name_plural = 'Токены устройств'

    def __str__(self):
        return f'Token {self.token[:8]}... — {self.patient}'

    @property
    def is_expired(self):
        return timezone.now() >= self.expires_at

    @property
    def is_valid(self):
        return self.is_active and not self.is_expired


class Notification(models.Model):
    """Уведомление для врача."""

    class Type(models.TextChoices):
        PATIENT_TRANSFERRED = 'patient_transferred', 'Пациент передан'
        PATIENT_ADDED = 'patient_added', 'Пациент добавлен'
        QUIZ_COMPLETED = 'quiz_completed', 'Тест пройден'

    doctor = models.ForeignKey(
        Doctor,
        on_delete=models.CASCADE,
        related_name='notifications',
        verbose_name='Врач',
    )
    type = models.CharField(
        'Тип', max_length=30,
        choices=Type.choices,
    )
    message = models.TextField('Сообщение')
    data = models.JSONField('Данные', default=dict, blank=True)
    is_read = models.BooleanField('Прочитано', default=False, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'Уведомление'
        verbose_name_plural = 'Уведомления'
        ordering = ['-created_at']

    def __str__(self):
        status = '✓' if self.is_read else '●'
        return f'{status} {self.get_type_display()} — {self.doctor}'


class Release(models.Model):
    """Собранный APK пациентского приложения, доступный для скачивания.

    Реестр привязан к стенду: на каждом хосте свой ENVIRONMENT (dev/preprod/prod),
    поэтому flavor здесь всегда константный и в модели не хранится — при нужде
    берётся из settings.ENVIRONMENT.
    """

    version_name = models.CharField('Версия', max_length=50)  # напр. 0.6.0
    version_code = models.PositiveIntegerField('Номер сборки')  # напр. 2
    apk = models.FileField('APK', upload_to='releases/')
    file_size = models.PositiveBigIntegerField('Размер, байт', default=0)
    commit_sha = models.CharField('Git commit', max_length=40, blank=True)
    notes = models.TextField('Описание релиза', blank=True)
    is_default = models.BooleanField('Дефолтный релиз', default=False)
    created_at = models.DateTimeField('Собран', auto_now_add=True)

    class Meta:
        verbose_name = 'Релиз APK'
        verbose_name_plural = 'Релизы APK'
        ordering = ['-created_at']
        constraints = [
            # версия уникальна в реестре стенда
            models.UniqueConstraint(
                fields=['version_name', 'version_code'],
                name='uniq_release_version',
            ),
            # не более одного дефолтного релиза
            models.UniqueConstraint(
                fields=['is_default'],
                condition=models.Q(is_default=True),
                name='uniq_default_release',
            ),
        ]

    # Стабильное имя файла дефолтного релиза (раздаётся nginx/Django напрямую).
    LATEST_APK_NAME = 'latest.apk'

    def __str__(self):
        return f'{self.version_name}+{self.version_code}'

    @property
    def download_url(self):
        """Публичная ссылка на скачивание этого APK (без авторизации)."""
        if not self.apk:
            return ''
        return f'/releases/{os.path.basename(self.apk.name)}'

    @classmethod
    def latest_url(cls):
        """Стабильная ссылка на дефолтный релиз."""
        return f'/releases/{cls.LATEST_APK_NAME}'

    def set_default(self):
        """Сделать релиз дефолтным (снимает флаг с прежнего дефолта)."""
        with transaction.atomic():
            Release.objects.filter(is_default=True).exclude(pk=self.pk).update(
                is_default=False
            )
            if not self.is_default:
                self.is_default = True
                self.save(update_fields=['is_default'])
        self._sync_latest_apk()

    def _sync_latest_apk(self):
        """Скопировать дефолтный APK в стабильный путь releases/latest.apk.

        Отдельный неизменный путь нужен, чтобы nginx (локально) и Django (на
        стендах) отдавали «последний релиз» по постоянной ссылке.
        """
        if not self.apk:
            return
        releases_dir = os.path.join(settings.MEDIA_ROOT, 'releases')
        os.makedirs(releases_dir, exist_ok=True)
        latest = os.path.join(releases_dir, self.LATEST_APK_NAME)
        tmp = f'{latest}.tmp'
        with self.apk.open('rb') as src, open(tmp, 'wb') as dst:
            shutil.copyfileobj(src, dst)
        os.replace(tmp, latest)  # атомарная подмена
