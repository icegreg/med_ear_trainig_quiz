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
    UpdatePatientSchema,
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
def get_my_patients(request, search: str | None = None):
    """Список пациентов текущего врача. Поиск по фамилии/имени (icontains)."""
    from django.db.models import Count, Q
    qs = request.doctor.patients.select_related('user', 'starting_sound')
    if search:
        term = search.strip()
        if term:
            qs = qs.filter(
                Q(last_name__icontains=term) | Q(first_name__icontains=term)
            )
    qs = qs.annotate(
        _assigned_count=Count(
            'quiz_assignments',
            filter=Q(quiz_assignments__status=PatientQuizAssignment.Status.ASSIGNED),
        ),
        _completed_count=Count(
            'quiz_assignments',
            filter=Q(quiz_assignments__status=PatientQuizAssignment.Status.COMPLETED),
        ),
    ).order_by('last_name', 'first_name')
    return [_patient_dict(p) for p in qs]


def _patient_dict(p: Patient) -> dict:
    assigned = getattr(p, '_assigned_count', None)
    completed = getattr(p, '_completed_count', None)
    if assigned is None:
        assigned = p.quiz_assignments.filter(
            status=PatientQuizAssignment.Status.ASSIGNED
        ).count()
    if completed is None:
        completed = p.quiz_assignments.filter(
            status=PatientQuizAssignment.Status.COMPLETED
        ).count()
    return {
        'id': p.id,
        'username': p.user.username,
        'doctor_id': p.doctor_id,
        'last_name': p.last_name,
        'first_name': p.first_name,
        'patronymic': p.patronymic,
        'full_name': p.full_name,
        'starting_sound_id': p.starting_sound_id,
        'starting_sound_url': p.starting_sound.file.url if p.starting_sound else None,
        'birth_date': p.birth_date,
        'assigned_count': assigned,
        'completed_count': completed,
        'created_at': p.created_at,
    }


@router.post('/patients', response={200: CreatePatientResponseSchema, 400: ErrorSchema})
def create_patient(request, payload: CreatePatientSchema):
    """Создать нового пациента и назначить текущему врачу."""
    if User.objects.filter(username=payload.username).exists():
        return 400, {'status': 'error', 'message': 'Пользователь с таким логином уже существует.'}

    user = User.objects.create_user(
        username=payload.username,
        password=payload.password,
    )
    patient = Patient.objects.create(
        user=user,
        doctor=request.doctor,
        last_name=payload.last_name,
        first_name=payload.first_name,
        patronymic=payload.patronymic,
        birth_date=payload.birth_date,
    )
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
    return 200, _patient_dict(patient)


@router.patch(
    '/patients/{patient_id}',
    response={200: PatientSchema, 404: ErrorSchema},
)
def update_patient(request, patient_id: int, payload: UpdatePatientSchema):
    """Обновить данные пациента (ФИО, дата рождения)."""
    patient = get_object_or_404(Patient, id=patient_id, doctor=request.doctor)
    data = payload.dict(exclude_unset=True)
    updatable = {'last_name', 'first_name', 'patronymic', 'birth_date'}
    fields = []
    for key, value in data.items():
        if key in updatable:
            setattr(patient, key, value if value is not None else (None if key == 'birth_date' else ''))
            fields.append(key)
    if fields:
        patient.save(update_fields=fields)
    return 200, _patient_dict(patient)


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


@router.delete(
    '/patients/{patient_id}/assignments/{assignment_id}',
    response={200: ErrorSchema, 400: ErrorSchema, 404: ErrorSchema},
)
def unassign_quiz(request, patient_id: int, assignment_id: int):
    """Снять назначение теста (только если не пройден)."""
    patient = get_object_or_404(Patient, id=patient_id, doctor=request.doctor)
    assignment = get_object_or_404(
        PatientQuizAssignment, id=assignment_id, patient=patient,
    )
    if assignment.status == PatientQuizAssignment.Status.COMPLETED:
        return 400, {'status': 'error', 'message': 'Нельзя снять пройденный тест.'}
    assignment.delete()
    return 200, {'status': 'ok', 'message': 'Назначение снято.'}


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

@router.get('/quizzes/{quiz_id}/audio', response={200: list[AudioFileSchema], 404: ErrorSchema})
def get_quiz_audio(request, quiz_id: int):
    """Список аудио-файлов, входящих в тест (из audio_files и questions.audio_file)."""
    quiz = get_object_or_404(Quiz, id=quiz_id)
    audio_ids = set(quiz.audio_files.values_list('id', flat=True))
    audio_ids.update(
        quiz.questions.exclude(audio_file__isnull=True)
        .values_list('audio_file_id', flat=True)
    )
    audio_files = AudioFile.objects.filter(id__in=audio_ids)
    return 200, [
        {
            'id': af.id,
            'title': af.title,
            'file': af.file.url,
            'category_id': af.category_id,
            'duration_seconds': af.duration_seconds,
            'uploaded_at': af.uploaded_at,
        }
        for af in audio_files
    ]


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
