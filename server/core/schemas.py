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


# --- Patient ---

class PatientSchema(Schema):
    id: int
    username: str
    doctor_id: UUID | None
    created_at: datetime


# --- Audio ---

class AudioFileSchema(Schema):
    id: int
    title: str
    file: str
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
