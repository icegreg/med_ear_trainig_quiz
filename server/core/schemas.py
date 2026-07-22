from datetime import date, datetime
from uuid import UUID

from ninja import Schema


# --- Doctor ---

class DoctorSchema(Schema):
    id: UUID
    last_name: str
    first_name: str
    patronymic: str
    clinic: str
    created_at: datetime


class DoctorListSchema(Schema):
    id: UUID
    last_name: str
    first_name: str
    patronymic: str
    clinic: str


# --- Clinic ---

class ClinicSchema(Schema):
    id: int
    name: str
    abbreviation: str
    address: str = ''


# --- Patient ---

class PatientSchema(Schema):
    id: int
    username: str
    doctor_id: UUID | None
    clinic_id: int | None = None
    clinic_name: str | None = None
    last_name: str = ''
    first_name: str = ''
    patronymic: str = ''
    full_name: str = ''
    starting_sound_id: int | None = None
    starting_sound_url: str | None = None
    birth_date: date | None = None
    assigned_count: int = 0
    completed_count: int = 0
    unreviewed_count: int = 0
    logging_enabled: bool = False
    created_at: datetime


class ClientLogEntrySchema(Schema):
    """Одна запись клиентского лога (отдельный HTTP-запрос приложения)."""
    client_ts: str
    method: str
    path: str
    status_code: int | None = None
    duration_ms: int | None = None
    error_type: str | None = None
    error_message: str | None = None
    request_payload: dict | list | str | None = None
    response_body: str | None = None
    app_version: str | None = None
    build_number: str | None = None
    platform: str | None = None
    flavor: str | None = None


class ClientLogBatchSchema(Schema):
    entries: list[ClientLogEntrySchema]


class ClientLogResponseSchema(Schema):
    enabled: bool
    accepted: int = 0


class CreatePatientSchema(Schema):
    username: str
    password: str
    clinic_id: int | None = None
    last_name: str = ''
    first_name: str = ''
    patronymic: str = ''
    birth_date: date | None = None


class UpdatePatientSchema(Schema):
    last_name: str | None = None
    first_name: str | None = None
    patronymic: str | None = None
    birth_date: date | None = None


class CreatePatientResponseSchema(Schema):
    id: int
    username: str


class SuggestLoginSchema(Schema):
    last_name: str = ''
    first_name: str = ''
    patronymic: str = ''
    birth_date: date | None = None
    clinic_id: int | None = None


class LoginSuggestionSchema(Schema):
    login: str


class ResetPasswordSchema(Schema):
    new_password: str


class ResetPasswordResponseSchema(Schema):
    id: int
    username: str


class MarkViewedResponseSchema(Schema):
    reviewed: int


class SetStartingSoundSchema(Schema):
    audio_file_id: int | None = None


class ChangePasswordSchema(Schema):
    old_password: str
    new_password: str


# --- Audio Category ---

class AudioCategorySchema(Schema):
    id: int
    name: str
    parent_id: int | None


class AudioCategoryTreeSchema(Schema):
    id: int
    name: str
    children: list['AudioCategoryTreeSchema'] = []


class CreateCategorySchema(Schema):
    name: str
    parent_id: int | None = None


class RenameCategorySchema(Schema):
    name: str


class MoveAudioSchema(Schema):
    category_id: int


# --- Audio ---

class AudioFileSchema(Schema):
    id: int
    title: str
    file: str
    category_id: int | None
    duration_seconds: int | None
    uploaded_at: datetime


# --- Quiz ---

class QuizQuestionSchema(Schema):
    id: int
    audio_file_id: int | None
    text: str
    options: list
    order: int


class QuizListSchema(Schema):
    id: int
    title: str
    description: str
    status: str
    assigned_at: datetime
    starts_at: datetime | None
    ends_at: datetime | None
    is_available: bool
    is_upcoming: bool
    is_expired: bool
    days_until_deadline: int | None


class QuizDetailSchema(Schema):
    id: int
    title: str
    description: str
    questions: list[QuizQuestionSchema]
    audio_file_ids: list[int]


class QuizSummarySchema(Schema):
    id: int
    title: str
    description: str
    question_count: int
    created_at: datetime


class QuizWithAudioSchema(QuizSummarySchema):
    """Сводка теста + входящие в него аудио (чтобы не дёргать /audio отдельно)."""
    audio_files: list[AudioFileSchema]


class CreateQuizSchema(Schema):
    # Пустой title → сервер сгенерирует «Тест № N. ДД.ММ.ГГГГ» для врача.
    title: str = ''
    description: str = ''
    sample_ids: list[int]


class SuggestedTitleSchema(Schema):
    title: str


# --- Assignments ---

class AssignQuizSchema(Schema):
    quiz_id: int
    starts_at: datetime | None = None
    ends_at: datetime | None = None


class AssignmentSchema(Schema):
    id: int
    quiz_id: int
    quiz_title: str
    status: str
    assigned_at: datetime
    starts_at: datetime | None
    ends_at: datetime | None
    completed_at: datetime | None
    is_expired: bool = False


# --- Results ---

class AnswerItem(Schema):
    question_id: int
    answer: str


class SubmitResultSchema(Schema):
    answers: list[AnswerItem]


class QuizResultSchema(Schema):
    assignment_id: int
    quiz_title: str
    answers: list
    score: int | None
    submitted_at: datetime


# --- Разбор результата по вопросам ---

class BreakdownItemSchema(Schema):
    """Одна строка разбора — вопрос, что ответил пациент и что было верно."""
    question_id: int
    order: int
    text: str
    audio_id: int | None
    audio_title: str | None
    audio_url: str | None
    audio_is_deleted: bool = False
    patient_answer: str
    correct_answer: str | None
    # None — вопрос удалён из квиза, правильный ответ неизвестен.
    is_correct: bool | None
    question_deleted: bool = False


class ResultBreakdownSchema(Schema):
    assignment_id: int
    quiz_title: str
    submitted_at: datetime
    score: int
    total: int
    percent: float
    questions: list[BreakdownItemSchema]


# --- Patient stats (карточка пациента у врача) ---

class StatsPointSchema(Schema):
    """Точка на графике динамики — один пройденный тест."""
    assignment_id: int
    quiz_title: str
    score: int
    total: int
    percent: float
    submitted_at: datetime


class SoundErrorSchema(Schema):
    """Ошибки пациента по одному звуку (агрегат по всем его тестам)."""
    audio_id: int | None
    title: str
    category: str | None
    answered: int
    errors: int
    error_percent: float
    is_deleted: bool = False


class AdherenceSchema(Schema):
    """Приверженность: сколько назначено/пройдено и как быстро проходит."""
    assigned: int
    completed: int
    expired: int
    upcoming: int
    completion_lag_days: list[int]
    avg_completion_days: float | None


class ActivityDaySchema(Schema):
    """Один день календаря активности: сколько тестов сдано."""
    date: date
    quizzes: int


class ActivitySchema(Schema):
    """Календарь активности: дни с пройденными тестами и последний вход.

    last_seen_at — максимум по DeviceToken.last_used_at. Это одна отметка на
    токен, а не история заходов, поэтому в календарь она не попадает.
    """
    days: list[ActivityDaySchema]
    last_seen_at: datetime | None


class PatientStatsSchema(Schema):
    dynamics: list[StatsPointSchema]
    sound_errors: list[SoundErrorSchema]
    adherence: AdherenceSchema
    activity: ActivitySchema


class ResultConfirmationSchema(Schema):
    status: str
    message: str


# --- Patient transfer ---

class TransferPatientSchema(Schema):
    patient_id: int
    to_doctor_id: UUID


class TransferResultSchema(Schema):
    status: str
    message: str


# --- Notifications ---

class NotificationSchema(Schema):
    id: int
    type: str
    message: str
    data: dict
    is_read: bool
    created_at: datetime


class NotificationsListSchema(Schema):
    notifications: list[NotificationSchema]
    unread_count: int


# --- Releases (APK) ---

class ReleaseSchema(Schema):
    version_name: str
    is_default: bool
    file_size: int  # выводится из файла (property модели), не хранимое поле
    created_at: datetime
    download_url: str


# --- Errors ---

class ErrorSchema(Schema):
    status: str
    message: str
