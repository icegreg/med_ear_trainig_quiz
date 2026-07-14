from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from ninja import Router

from .. import client_logs
from ..models import QuizResult
from ..schemas import (
    ChangePasswordSchema,
    ClientLogBatchSchema,
    ClientLogResponseSchema,
    ErrorSchema,
    PatientSchema,
    QuizListSchema,
    QuizResultSchema,
    ResultConfirmationSchema,
)

router = Router()


@router.get('/me', response=PatientSchema)
def get_my_profile(request):
    """Профиль текущего пациента."""
    patient = request.patient
    return {
        'id': patient.id,
        'username': patient.user.username,
        'doctor_id': patient.doctor_id,
        'starting_sound_id': patient.starting_sound_id,
        'starting_sound_url': (patient.starting_sound.file_url or None) if patient.starting_sound else None,
        'logging_enabled': patient.effective_logging_enabled,
        'created_at': patient.created_at,
    }


@router.get('/me/quizzes', response=list[QuizListSchema])
def get_my_quizzes(request):
    """Все тесты пациента: пройденные, доступные, будущие, просроченные."""
    assignments = request.patient.quiz_assignments.select_related('quiz').all()
    return [
        {
            'id': a.quiz.id,
            'title': a.quiz.title,
            'description': a.quiz.description,
            'status': a.status,
            'assigned_at': a.assigned_at,
            'starts_at': a.starts_at,
            'ends_at': a.ends_at,
            'is_available': a.is_available,
            'is_upcoming': a.is_upcoming,
            'is_expired': a.is_expired,
            'days_until_deadline': a.days_until_deadline,
        }
        for a in assignments
    ]


@router.get('/me/results', response=list[QuizResultSchema])
def get_my_results(request):
    """Все результаты тестов текущего пациента."""
    results = QuizResult.objects.filter(
        assignment__patient=request.patient
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


@router.post(
    '/me/change-password',
    response={200: ResultConfirmationSchema, 400: ErrorSchema},
)
def change_password(request, payload: ChangePasswordSchema):
    """Смена пароля текущего пациента: проверка старого + установка нового."""
    user = request.patient.user

    if not user.check_password(payload.old_password):
        return 400, {'status': 'error', 'message': 'Неверный текущий пароль.'}

    if payload.new_password == payload.old_password:
        return 400, {
            'status': 'error',
            'message': 'Новый пароль должен отличаться от текущего.',
        }

    try:
        validate_password(payload.new_password, user=user)
    except ValidationError as exc:
        return 400, {'status': 'error', 'message': ' '.join(exc.messages)}

    user.set_password(payload.new_password)
    user.save(update_fields=['password'])

    return 200, {'status': 'ok', 'message': 'Пароль успешно изменён.'}


@router.post('/logs', response=ClientLogResponseSchema)
def post_client_logs(request, batch: ClientLogBatchSchema):
    """Принимает batch клиентских логов от приложения пациента.

    Если у пациента (или его врача) логирование выключено — записи отбрасываются,
    клиент получит {enabled: false} и должен прекратить отправку.
    """
    patient = request.patient
    if not patient.effective_logging_enabled:
        return {'enabled': False, 'accepted': 0}

    entries = [e.dict() for e in batch.entries]
    accepted = client_logs.append_entries(patient.id, entries)
    return {'enabled': True, 'accepted': accepted}
