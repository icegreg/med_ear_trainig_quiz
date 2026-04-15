from datetime import datetime
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


# --- Patient ---

class PatientSchema(Schema):
    id: int
    username: str
    doctor_id: UUID | None
    starting_sound_id: int | None = None
    starting_sound_url: str | None = None
    created_at: datetime


class CreatePatientSchema(Schema):
    username: str
    password: str


class CreatePatientResponseSchema(Schema):
    id: int
    username: str


class SetStartingSoundSchema(Schema):
    audio_file_id: int | None = None


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


# --- Errors ---

class ErrorSchema(Schema):
    status: str
    message: str
