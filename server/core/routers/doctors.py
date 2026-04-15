from uuid import UUID

from django.contrib.auth.models import User
from django.db import IntegrityError
from django.shortcuts import get_object_or_404
from ninja import Query, Router

from ..models import (
    AudioCategory,
    AudioFile,
    Doctor,
    Notification,
    Patient,
    PatientQuizAssignment,
    Quiz,
    QuizResult,
)
from ..schemas import (
    AssignmentSchema,
    AssignQuizSchema,
    AudioCategorySchema,
    AudioCategoryTreeSchema,
    AudioFileSchema,
    CreateCategorySchema,
    CreatePatientResponseSchema,
    CreatePatientSchema,
    DoctorListSchema,
    DoctorSchema,
    ErrorSchema,
    MoveAudioSchema,
    NotificationsListSchema,
    NotificationSchema,
    PatientSchema,
    QuizResultSchema,
    QuizSummarySchema,
    RenameCategorySchema,
    SetStartingSoundSchema,
    TransferPatientSchema,
    TransferResultSchema,
)

router = Router()


# ─── Profile ────────────────────────────────────────────────────────────

@router.get('/me', response=DoctorSchema)
def get_doctor_profile(request):
    """Профиль текущего врача."""
    return request.doctor


@router.get('/list', response=list[DoctorListSchema])
def list_doctors(request):
    """Список всех врачей (для выбора при передаче пациента)."""
    return Doctor.objects.exclude(id=request.doctor.id).values(
        'id', 'last_name', 'first_name', 'patronymic', 'clinic',
    )


# ─── Patients ───────────────────────────────────────────────────────────

@router.get('/me/patients', response=list[PatientSchema])
def get_my_patients(request):
    """Список пациентов текущего врача."""
    patients = request.doctor.patients.select_related('user', 'starting_sound').all()
    return [
        {
            'id': p.id,
            'username': p.user.username,
            'doctor_id': p.doctor_id,
            'starting_sound_id': p.starting_sound_id,
            'starting_sound_url': p.starting_sound.file.url if p.starting_sound else None,
            'created_at': p.created_at,
        }
        for p in patients
    ]


@router.post('/patients', response={200: CreatePatientResponseSchema, 400: ErrorSchema})
def create_patient(request, payload: CreatePatientSchema):
    """Создать нового пациента и назначить текущему врачу."""
    if User.objects.filter(username=payload.username).exists():
        return 400, {'status': 'error', 'message': 'Пользователь с таким логином уже существует.'}

    user = User.objects.create_user(
        username=payload.username,
        password=payload.password,
    )
    patient = Patient.objects.create(user=user, doctor=request.doctor)
    return 200, {'id': patient.id, 'username': user.username}


@router.put(
    '/patients/{patient_id}/starting-sound',
    response={200: PatientSchema, 400: ErrorSchema, 404: ErrorSchema},
)
def set_starting_sound(request, patient_id: int, payload: SetStartingSoundSchema):
    """Установить или убрать стартовый звук для пациента."""
    patient = get_object_or_404(Patient, id=patient_id, doctor=request.doctor)

    if payload.audio_file_id is not None:
        audio = AudioFile.objects.filter(id=payload.audio_file_id).first()
        if not audio:
            return 404, {'status': 'error', 'message': 'Аудио-файл не найден.'}
        patient.starting_sound = audio
    else:
        patient.starting_sound = None

    patient.save()
    return 200, {
        'id': patient.id,
        'username': patient.user.username,
        'doctor_id': patient.doctor_id,
        'starting_sound_id': patient.starting_sound_id,
        'starting_sound_url': patient.starting_sound.file.url if patient.starting_sound else None,
        'created_at': patient.created_at,
    }


# ─── Patient results ───────────────────────────────────────────────────

@router.get('/patients/{patient_id}/results', response=list[QuizResultSchema])
def get_patient_results(request, patient_id: int):
    """Все результаты тестов конкретного пациента (для врача)."""
    patient = get_object_or_404(Patient, id=patient_id, doctor=request.doctor)
    results = QuizResult.objects.filter(
        assignment__patient=patient
    ).select_related('assignment__quiz')
    return [
        {
            'assignment_id': r.assignment_id,
            'quiz_title': r.assignment.quiz.title,
            'answers': r.answers,
            'score': r.score,
            'submitted_at': r.submitted_at,
        }
        for r in results
    ]


# ─── Patient assignments ───────────────────────────────────────────────

@router.get('/patients/{patient_id}/assignments', response=list[AssignmentSchema])
def get_patient_assignments(request, patient_id: int):
    """Назначения тестов пациента."""
    patient = get_object_or_404(Patient, id=patient_id, doctor=request.doctor)
    assignments = PatientQuizAssignment.objects.filter(
        patient=patient
    ).select_related('quiz').order_by('-assigned_at')
    return [
        {
            'id': a.id,
            'quiz_id': a.quiz_id,
            'quiz_title': a.quiz.title,
            'status': a.status,
            'assigned_at': a.assigned_at,
            'starts_at': a.starts_at,
            'ends_at': a.ends_at,
            'completed_at': a.completed_at,
        }
        for a in assignments
    ]


@router.post(
    '/patients/{patient_id}/assign-quiz',
    response={200: AssignmentSchema, 400: ErrorSchema},
)
def assign_quiz(request, patient_id: int, payload: AssignQuizSchema):
    """Назначить тест пациенту."""
    patient = get_object_or_404(Patient, id=patient_id, doctor=request.doctor)
    quiz = get_object_or_404(Quiz, id=payload.quiz_id)

    if PatientQuizAssignment.objects.filter(patient=patient, quiz=quiz).exists():
        return 400, {'status': 'error', 'message': 'Этот тест уже назначен данному пациенту.'}

    assignment = PatientQuizAssignment.objects.create(
        patient=patient,
        quiz=quiz,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
    )
    return 200, {
        'id': assignment.id,
        'quiz_id': assignment.quiz_id,
        'quiz_title': quiz.title,
        'status': assignment.status,
        'assigned_at': assignment.assigned_at,
        'starts_at': assignment.starts_at,
        'ends_at': assignment.ends_at,
        'completed_at': assignment.completed_at,
    }


# ─── Quizzes ────────────────────────────────────────────────────────────

@router.get('/quizzes', response=list[QuizSummarySchema])
def list_quizzes(request):
    """Все доступные квизы."""
    quizzes = Quiz.objects.prefetch_related('questions').all()
    return [
        {
            'id': q.id,
            'title': q.title,
            'description': q.description,
            'question_count': q.questions.count(),
            'created_at': q.created_at,
        }
        for q in quizzes
    ]


# ─── Audio Library ──────────────────────────────────────────────────────

@router.get('/audio-library', response=list[AudioFileSchema])
def list_audio(request, category_id: int | None = None):
    """Список аудио-файлов. Фильтр по категории опционален."""
    qs = AudioFile.objects.select_related('category').all()
    if category_id is not None:
        qs = qs.filter(category_id=category_id)
    return [
        {
            'id': a.id,
            'title': a.title,
            'file': a.file.url,
            'category_id': a.category_id,
            'duration_seconds': a.duration_seconds,
            'uploaded_at': a.uploaded_at,
        }
        for a in qs
    ]


@router.get('/audio-library/categories', response=list[AudioCategoryTreeSchema])
def list_categories(request):
    """Дерево категорий аудио."""
    categories = AudioCategory.objects.all()
    cat_map = {}
    for cat in categories:
        cat_map[cat.id] = {
            'id': cat.id,
            'name': cat.name,
            'parent_id': cat.parent_id,
            'children': [],
        }

    roots = []
    for cat_id, cat_data in cat_map.items():
        parent_id = cat_data['parent_id']
        if parent_id and parent_id in cat_map:
            cat_map[parent_id]['children'].append(cat_data)
        else:
            roots.append(cat_data)

    return roots


@router.post(
    '/audio-library/categories',
    response={200: AudioCategorySchema, 400: ErrorSchema},
)
def create_category(request, payload: CreateCategorySchema):
    """Создать категорию аудио."""
    if payload.parent_id is not None:
        parent = AudioCategory.objects.filter(id=payload.parent_id).first()
        if not parent:
            return 400, {'status': 'error', 'message': 'Родительская категория не найдена.'}
    cat = AudioCategory.objects.create(name=payload.name, parent_id=payload.parent_id)
    return 200, {'id': cat.id, 'name': cat.name, 'parent_id': cat.parent_id}


@router.put(
    '/audio-library/categories/{category_id}',
    response={200: AudioCategorySchema, 400: ErrorSchema},
)
def rename_category(request, category_id: int, payload: RenameCategorySchema):
    """Переименовать категорию."""
    cat = get_object_or_404(AudioCategory, id=category_id)
    default = AudioCategory.get_default()
    if cat.id == default.id:
        return 400, {'status': 'error', 'message': 'Нельзя переименовать корневую категорию.'}
    cat.name = payload.name
    cat.save()
    return 200, {'id': cat.id, 'name': cat.name, 'parent_id': cat.parent_id}


@router.delete(
    '/audio-library/categories/{category_id}',
    response={200: ErrorSchema, 400: ErrorSchema},
)
def delete_category(request, category_id: int):
    """Удалить категорию. Файлы и подкатегории переходят в корневую."""
    cat = get_object_or_404(AudioCategory, id=category_id)
    default = AudioCategory.get_default()
    if cat.id == default.id:
        return 400, {'status': 'error', 'message': 'Нельзя удалить корневую категорию.'}

    # Перенести аудио-файлы в корневую
    AudioFile.all_objects.filter(category=cat).update(category=default)
    # Перенести подкатегории к родителю удаляемой (или в root)
    AudioCategory.objects.filter(parent=cat).update(parent=cat.parent)

    cat.delete()
    return 200, {'status': 'ok', 'message': 'Категория удалена.'}


@router.put(
    '/audio-library/{audio_id}/move',
    response={200: AudioFileSchema, 404: ErrorSchema},
)
def move_audio(request, audio_id: int, payload: MoveAudioSchema):
    """Переместить аудио-файл в другую категорию."""
    audio = get_object_or_404(AudioFile, id=audio_id)
    category = get_object_or_404(AudioCategory, id=payload.category_id)
    audio.category = category
    audio.save(update_fields=['category'])
    return 200, {
        'id': audio.id,
        'title': audio.title,
        'file': audio.file.url,
        'category_id': audio.category_id,
        'duration_seconds': audio.duration_seconds,
        'uploaded_at': audio.uploaded_at,
    }


# ─── Transfer ───────────────────────────────────────────────────────────

@router.post('/transfer-patient', response={200: TransferResultSchema, 400: TransferResultSchema})
def transfer_patient(request, payload: TransferPatientSchema):
    """Передать пациента другому врачу."""
    patient = get_object_or_404(
        Patient, id=payload.patient_id, doctor=request.doctor
    )
    target_doctor = get_object_or_404(Doctor, id=payload.to_doctor_id)

    if target_doctor == request.doctor:
        return 400, {'status': 'error', 'message': 'Нельзя передать пациента самому себе.'}

    patient.doctor = target_doctor
    patient.save()

    # Уведомление исходному врачу (текущий пользователь)
    Notification.objects.create(
        doctor=request.doctor,
        type=Notification.Type.PATIENT_TRANSFERRED,
        message=f'Пациент {patient.user.username} передан врачу {target_doctor}.',
        data={
            'patient_id': patient.id,
            'patient_username': patient.user.username,
            'to_doctor_id': str(target_doctor.id),
        },
    )

    return 200, {
        'status': 'ok',
        'message': f'Пациент передан врачу {target_doctor.id}.',
    }


# ─── Notifications ──────────────────────────────────────────────────────

@router.get('/notifications', response=NotificationsListSchema)
def list_notifications(request, unread_only: bool = False):
    """Список уведомлений врача."""
    qs = Notification.objects.filter(doctor=request.doctor)
    unread_count = qs.filter(is_read=False).count()

    if unread_only:
        qs = qs.filter(is_read=False)

    notifications = [
        {
            'id': n.id,
            'type': n.type,
            'message': n.message,
            'data': n.data,
            'is_read': n.is_read,
            'created_at': n.created_at,
        }
        for n in qs[:100]
    ]
    return {'notifications': notifications, 'unread_count': unread_count}


@router.post(
    '/notifications/{notification_id}/read',
    response={200: NotificationSchema, 404: ErrorSchema},
)
def mark_notification_read(request, notification_id: int):
    """Отметить уведомление как прочитанное."""
    notification = Notification.objects.filter(
        id=notification_id, doctor=request.doctor
    ).first()
    if not notification:
        return 404, {'status': 'error', 'message': 'Уведомление не найдено.'}

    notification.is_read = True
    notification.save(update_fields=['is_read'])
    return 200, {
        'id': notification.id,
        'type': notification.type,
        'message': notification.message,
        'data': notification.data,
        'is_read': notification.is_read,
        'created_at': notification.created_at,
    }
