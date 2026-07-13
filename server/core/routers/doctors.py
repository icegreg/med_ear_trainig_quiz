from datetime import date
from uuid import UUID

from django.contrib.auth.models import User
from django.db import IntegrityError
from django.db.models import Max
from django.shortcuts import get_object_or_404
from django.utils import timezone
from ninja import Query, Router

from ..models import (
    AudioCategory,
    AudioFile,
    Clinic,
    default_question_options,
    Doctor,
    Notification,
    Patient,
    PatientQuizAssignment,
    Quiz,
    QuizQuestion,
    QuizResult,
)
from ..schemas import (
    AssignmentSchema,
    AssignQuizSchema,
    AudioCategorySchema,
    AudioCategoryTreeSchema,
    AudioFileSchema,
    ClinicSchema,
    CreateCategorySchema,
    CreatePatientResponseSchema,
    CreatePatientSchema,
    CreateQuizSchema,
    DoctorListSchema,
    DoctorSchema,
    ErrorSchema,
    LoginSuggestionSchema,
    MarkViewedResponseSchema,
    MoveAudioSchema,
    NotificationsListSchema,
    NotificationSchema,
    PatientSchema,
    PatientStatsSchema,
    QuizResultSchema,
    QuizSummarySchema,
    QuizWithAudioSchema,
    RenameCategorySchema,
    ResultBreakdownSchema,
    ResetPasswordResponseSchema,
    ResetPasswordSchema,
    SetStartingSoundSchema,
    SuggestedTitleSchema,
    SuggestLoginSchema,
    TransferPatientSchema,
    TransferResultSchema,
    UpdatePatientSchema,
)
from ..utils import generate_patient_login, get_client_ip
from .. import client_logs, doctor_logs

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
    qs = request.doctor.patients.select_related('user', 'starting_sound', 'clinic')
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
        _unreviewed_count=Count(
            'quiz_assignments',
            filter=Q(
                quiz_assignments__status=PatientQuizAssignment.Status.COMPLETED,
                quiz_assignments__reviewed_at__isnull=True,
            ),
        ),
    ).order_by('last_name', 'first_name')
    return [_patient_dict(p) for p in qs]


def _patient_dict(p: Patient) -> dict:
    assigned = getattr(p, '_assigned_count', None)
    completed = getattr(p, '_completed_count', None)
    unreviewed = getattr(p, '_unreviewed_count', None)
    if assigned is None:
        assigned = p.quiz_assignments.filter(
            status=PatientQuizAssignment.Status.ASSIGNED
        ).count()
    if completed is None:
        completed = p.quiz_assignments.filter(
            status=PatientQuizAssignment.Status.COMPLETED
        ).count()
    if unreviewed is None:
        unreviewed = p.quiz_assignments.filter(
            status=PatientQuizAssignment.Status.COMPLETED,
            reviewed_at__isnull=True,
        ).count()
    return {
        'id': p.id,
        'username': p.user.username,
        'doctor_id': p.doctor_id,
        'clinic_id': p.clinic_id,
        'clinic_name': p.clinic.name if p.clinic else None,
        'last_name': p.last_name,
        'first_name': p.first_name,
        'patronymic': p.patronymic,
        'full_name': p.full_name,
        'starting_sound_id': p.starting_sound_id,
        'starting_sound_url': p.starting_sound.file.url if p.starting_sound else None,
        'birth_date': p.birth_date,
        'assigned_count': assigned,
        'completed_count': completed,
        'unreviewed_count': unreviewed,
        'created_at': p.created_at,
    }


@router.get('/clinics', response=list[ClinicSchema])
def list_clinics(request):
    """Список всех клиник (для селектора при заведении пациента)."""
    return Clinic.objects.all()


@router.post('/patients', response={200: CreatePatientResponseSchema, 400: ErrorSchema})
def create_patient(request, payload: CreatePatientSchema):
    """Создать нового пациента и назначить текущему врачу."""
    if User.objects.filter(username=payload.username).exists():
        return 400, {'status': 'error', 'message': 'Пользователь с таким логином уже существует.'}

    clinic = None
    if payload.clinic_id is not None:
        clinic = Clinic.objects.filter(id=payload.clinic_id).first()
        if clinic is None:
            return 400, {'status': 'error', 'message': 'Клиника не найдена.'}

    user = User.objects.create_user(
        username=payload.username,
        password=payload.password,
    )
    patient = Patient.objects.create(
        user=user,
        doctor=request.doctor,
        clinic=clinic,
        last_name=payload.last_name,
        first_name=payload.first_name,
        patronymic=payload.patronymic,
        birth_date=payload.birth_date,
    )
    return 200, {'id': patient.id, 'username': user.username}


@router.post('/patients/suggest-login', response=LoginSuggestionSchema)
def suggest_patient_login(request, payload: SuggestLoginSchema):
    """Предложить свободный логин по ФИО.

    Формат: ``аббревиатура_клиники-фамилияинициалы`` (напр. ``msk-ivanovps``);
    при дубликате добавляется порядковый номер (``msk-ivanovps2``). Без клиники —
    легаси-формат: ``фамилияинициалы`` + суффикс года рождения / автоинкремент.
    """
    clinic_abbr = ''
    if payload.clinic_id is not None:
        clinic = Clinic.objects.filter(id=payload.clinic_id).first()
        if clinic is not None:
            clinic_abbr = clinic.abbreviation

    login = generate_patient_login(
        last_name=payload.last_name,
        first_name=payload.first_name,
        patronymic=payload.patronymic,
        birth_date=payload.birth_date,
        clinic_abbr=clinic_abbr,
    )
    return {'login': login}


@router.post(
    '/patients/{patient_id}/mark-results-viewed',
    response={200: MarkViewedResponseSchema, 404: ErrorSchema},
)
def mark_results_viewed(request, patient_id: int):
    """Отметить все пройденные тесты пациента как просмотренные врачом."""
    patient = get_object_or_404(Patient, id=patient_id, doctor=request.doctor)
    count = PatientQuizAssignment.objects.filter(
        patient=patient,
        status=PatientQuizAssignment.Status.COMPLETED,
        reviewed_at__isnull=True,
    ).update(reviewed_at=timezone.now())
    if count:
        doctor_logs.append_action(
            request.doctor.id, 'review_results',
            patient=patient, detail=f'Просмотрено тестов: {count}',
            ip=get_client_ip(request),
        )
    return 200, {'reviewed': count}


@router.post(
    '/patients/{patient_id}/reset-password',
    response={200: ResetPasswordResponseSchema, 404: ErrorSchema},
)
def reset_patient_password(request, patient_id: int, payload: ResetPasswordSchema):
    """Сбросить пароль пациента текущего врача на новый."""
    patient = get_object_or_404(Patient, id=patient_id, doctor=request.doctor)
    user = patient.user
    user.set_password(payload.new_password)
    user.save(update_fields=['password'])

    ip = get_client_ip(request)
    # Лог врача — факт сброса, без самого пароля.
    doctor_logs.append_action(
        request.doctor.id, 'reset_password', patient=patient, ip=ip,
    )
    # Пометка в логе пациента — просто факт смены пароля, без пароля.
    client_logs.append_entries(patient.id, [{
        'client_ts': timezone.now().isoformat(),
        'method': 'SYSTEM',
        'path': 'Пароль изменён врачом',
        'event': 'password_changed',
        'status_code': None,
    }])
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


@router.get(
    '/results/{assignment_id}',
    response={200: ResultBreakdownSchema, 404: ErrorSchema},
)
def get_result_breakdown(request, assignment_id: int):
    """Разбор пройденного теста по вопросам: что спросили, что ответил пациент,
    что было верно."""
    result = get_object_or_404(
        QuizResult.objects.select_related('assignment__quiz'),
        assignment_id=assignment_id,
        assignment__patient__doctor=request.doctor,
    )

    answers = [a for a in result.answers if isinstance(a, dict)]
    questions = {
        q.id: q
        for q in QuizQuestion.objects.filter(
            id__in=[a.get('question_id') for a in answers]
        ).select_related('audio_file')
    }

    items = []
    for a in answers:
        question = questions.get(a.get('question_id'))
        patient_answer = str(a.get('answer', ''))
        if question is None:
            # Вопрос удалён из квиза: ответ пациента сохраняем, но сверить
            # его не с чем. Строку всё равно показываем — она часть теста.
            items.append({
                'question_id': a.get('question_id') or 0,
                # Удалённые вопросы — в конец списка.
                'order': 10**6,
                'text': 'Вопрос удалён из теста',
                'audio_id': None,
                'audio_title': None,
                'audio_url': None,
                'audio_is_deleted': False,
                'patient_answer': patient_answer,
                'correct_answer': None,
                'is_correct': None,
                'question_deleted': True,
            })
            continue

        audio = question.audio_file  # NULL (SET_NULL) или soft-deleted — не падаем
        items.append({
            'question_id': question.id,
            'order': question.order,
            'text': question.text,
            'audio_id': audio.id if audio else None,
            'audio_title': audio.title if audio else None,
            'audio_url': audio.file.url if audio and audio.file else None,
            'audio_is_deleted': bool(audio and audio.is_deleted),
            'patient_answer': patient_answer,
            'correct_answer': question.correct_answer,
            'is_correct': patient_answer == question.correct_answer,
            'question_deleted': False,
        })

    items.sort(key=lambda i: i['order'])
    total = len(items)
    score = result.score or 0

    return 200, {
        'assignment_id': result.assignment_id,
        'quiz_title': result.assignment.quiz.title,
        'submitted_at': result.submitted_at,
        'score': score,
        'total': total,
        'percent': round(score / total * 100, 1) if total else 0.0,
        'questions': items,
    }


@router.get('/patients/{patient_id}/stats', response=PatientStatsSchema)
def get_patient_stats(request, patient_id: int):
    """Статистика пациента: динамика, ошибки по звукам, приверженность, активность."""
    patient = get_object_or_404(Patient, id=patient_id, doctor=request.doctor)

    results = list(
        QuizResult.objects.filter(assignment__patient=patient)
        .select_related('assignment__quiz')
        .order_by('submitted_at')
    )

    # Тексты/правильные ответы вопросов, реально встреченных в ответах.
    question_ids = {
        a.get('question_id')
        for r in results
        for a in r.answers
        if isinstance(a, dict)
    }
    questions = {
        q.id: q
        for q in QuizQuestion.objects.filter(id__in=question_ids)
        .select_related('audio_file__category')
    }

    dynamics = []
    # audio_id -> [answered, errors, title, category, is_deleted]
    sounds: dict[int | None, dict] = {}

    for r in results:
        answers = [a for a in r.answers if isinstance(a, dict)]
        # Длина ответов — это число вопросов на момент сдачи (submit требует
        # ответа на все). Вопросы квиза могли измениться позже, поэтому берём
        # исторический снимок, а не текущий questions.count().
        total = len(answers) or r.assignment.quiz.questions.count()
        score = r.score or 0
        dynamics.append({
            'assignment_id': r.assignment_id,
            'quiz_title': r.assignment.quiz.title,
            'score': score,
            'total': total,
            'percent': round(score / total * 100, 1) if total else 0.0,
            'submitted_at': r.submitted_at,
        })

        for a in answers:
            question = questions.get(a.get('question_id'))
            if question is None:
                # Вопрос удалён из квиза — правильный ответ неизвестен, пропускаем.
                continue
            audio = question.audio_file  # может быть NULL (SET_NULL) или soft-deleted
            key = audio.id if audio else None
            bucket = sounds.setdefault(key, {
                'audio_id': key,
                'title': audio.title if audio else 'Без звука',
                'category': audio.category.name if audio and audio.category else None,
                'is_deleted': bool(audio and audio.is_deleted),
                'answered': 0,
                'errors': 0,
            })
            bucket['answered'] += 1
            if a.get('answer') != question.correct_answer:
                bucket['errors'] += 1

    sound_errors = [
        {**b, 'error_percent': round(b['errors'] / b['answered'] * 100, 1)}
        for b in sounds.values()
        if b['answered']
    ]
    # Сначала самые проблемные звуки — врач смотрит сверху вниз.
    sound_errors.sort(key=lambda b: (-b['error_percent'], -b['answered'], b['title']))

    assignments = list(patient.quiz_assignments.all())
    lags = [
        (a.completed_at - a.assigned_at).days
        for a in assignments
        if a.status == PatientQuizAssignment.Status.COMPLETED
        and a.completed_at and a.assigned_at
    ]
    adherence = {
        'assigned': sum(
            1 for a in assignments
            if a.status == PatientQuizAssignment.Status.ASSIGNED
        ),
        'completed': sum(
            1 for a in assignments
            if a.status == PatientQuizAssignment.Status.COMPLETED
        ),
        'expired': sum(1 for a in assignments if a.is_expired),
        'upcoming': sum(1 for a in assignments if a.is_upcoming),
        'completion_lag_days': lags,
        'avg_completion_days': round(sum(lags) / len(lags), 1) if lags else None,
    }

    # Календарь: агрегируем по локальной дате сервера, иначе тест, сданный
    # поздно вечером, «уезжает» в соседний день.
    days: dict[date, int] = {}
    for r in results:
        day = timezone.localdate(r.submitted_at)
        days[day] = days.get(day, 0) + 1

    last_seen_at = patient.device_tokens.aggregate(
        last=Max('last_used_at')
    )['last']

    activity = {
        'days': [
            {'date': day, 'quizzes': count}
            for day, count in sorted(days.items())
        ],
        'last_seen_at': last_seen_at,
    }

    return {
        'dynamics': dynamics,
        'sound_errors': sound_errors,
        'adherence': adherence,
        'activity': activity,
    }


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
            'is_expired': a.is_expired,
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
    quiz_title = assignment.quiz.title
    assignment.delete()
    doctor_logs.append_action(
        request.doctor.id, 'unassign_quiz',
        patient=patient, detail=quiz_title, ip=get_client_ip(request),
    )
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
    doctor_logs.append_action(
        request.doctor.id, 'assign_quiz',
        patient=patient, detail=quiz.title, ip=get_client_ip(request),
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
        'is_expired': assignment.is_expired,
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


def _suggested_quiz_title(doctor):
    """«Тест № N. ДД.ММ.ГГГГ», где N — порядковый номер теста этого врача."""
    number = Quiz.objects.filter(created_by=doctor).count() + 1
    date = timezone.localdate().strftime('%d.%m.%Y')
    return f'Тест № {number}. {date}'


@router.get('/quizzes/suggested-title', response=SuggestedTitleSchema)
def get_suggested_quiz_title(request):
    """Подсказка названия для нового теста (нумерация — по тестам врача)."""
    return {'title': _suggested_quiz_title(request.doctor)}


@router.post('/quizzes', response={200: QuizSummarySchema, 400: ErrorSchema})
def create_quiz(request, payload: CreateQuizSchema):
    """Создать тест из выбранных сэмплов (аудио из библиотеки).

    Каждый сэмпл становится отдельным вопросом «слышу / не слышу»
    (correct_answer = «да»). Порядок вопросов = порядок переданных id.
    Пустое название → генерируется «Тест № N. ДД.ММ.ГГГГ» для врача.
    """
    title = payload.title.strip() or _suggested_quiz_title(request.doctor)

    # Убираем дубли, сохраняя порядок выбора.
    seen = set()
    ordered_ids = []
    for sid in payload.sample_ids:
        if sid not in seen:
            seen.add(sid)
            ordered_ids.append(sid)

    if not ordered_ids:
        return 400, {'status': 'error', 'message': 'Выберите хотя бы один звук.'}

    samples = {a.id: a for a in AudioFile.objects.filter(id__in=ordered_ids)}
    missing = [sid for sid in ordered_ids if sid not in samples]
    if missing:
        return 400, {'status': 'error', 'message': 'Некоторые звуки не найдены.'}

    ordered = [samples[sid] for sid in ordered_ids]

    quiz = Quiz.objects.create(
        title=title,
        description=payload.description,
        created_by=request.doctor,
    )
    quiz.audio_files.add(*ordered)
    QuizQuestion.objects.bulk_create([
        QuizQuestion(
            quiz=quiz,
            audio_file=sample,
            text=sample.title,
            options=default_question_options(),
            correct_answer=QuizQuestion.Answer.YES,
            order=i,
        )
        for i, sample in enumerate(ordered)
    ])

    return 200, {
        'id': quiz.id,
        'title': quiz.title,
        'description': quiz.description,
        'question_count': quiz.questions.count(),
        'created_at': quiz.created_at,
    }


def _audio_payload(af):
    return {
        'id': af.id,
        'title': af.title,
        'file': af.file.url,
        'category_id': af.category_id,
        'duration_seconds': af.duration_seconds,
        'uploaded_at': af.uploaded_at,
    }


@router.get('/quizzes', response=list[QuizWithAudioSchema])
def list_quizzes(request):
    """Все доступные квизы вместе с входящими в них аудио.

    Аудио — объединение M2M `audio_files` и `questions.audio_file` (как в
    /quizzes/{id}/audio), удалённые исключаются. Prefetch убирает N+1.
    """
    quizzes = Quiz.objects.prefetch_related(
        'questions', 'audio_files', 'questions__audio_file'
    ).all()
    result = []
    for q in quizzes:
        audio_by_id = {
            af.id: af for af in q.audio_files.all() if af.deleted_at is None
        }
        for question in q.questions.all():
            af = question.audio_file
            if af is not None and af.deleted_at is None:
                audio_by_id[af.id] = af
        result.append({
            'id': q.id,
            'title': q.title,
            'description': q.description,
            'question_count': len(q.questions.all()),
            'created_at': q.created_at,
            'audio_files': [_audio_payload(af) for af in audio_by_id.values()],
        })
    return result


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
