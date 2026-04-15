from ninja import Router

from ..models import QuizResult
from ..schemas import (
    PatientSchema,
    QuizListSchema,
    QuizResultSchema,
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
        'starting_sound_url': patient.starting_sound.file.url if patient.starting_sound else None,
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
