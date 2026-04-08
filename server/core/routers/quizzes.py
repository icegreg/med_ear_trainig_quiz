from django.shortcuts import get_object_or_404
from django.utils import timezone
from ninja import Router

from ..models import AudioFile, PatientQuizAssignment, Quiz, QuizResult
from ..schemas import (
    AudioFileSchema,
    QuizDetailSchema,
    ResultConfirmationSchema,
    SubmitResultSchema,
)

router = Router()


def _check_available(assignment):
    """Проверяет доступность теста. Возвращает (ok, error_response) или (True, None)."""
    if assignment.is_upcoming:
        return False, (403, {
            'status': 'error',
            'message': 'Тест ещё не доступен. '
                       f'Начало: {assignment.starts_at.strftime("%d.%m.%Y %H:%M")}.',
        })
    if assignment.is_expired:
        return False, (403, {
            'status': 'error',
            'message': 'Срок прохождения теста истёк.',
        })
    return True, None


@router.get('/{quiz_id}', response={200: QuizDetailSchema, 403: ResultConfirmationSchema})
def get_quiz_detail(request, quiz_id: int):
    """Детальная информация по квизу. Недоступные тесты → 403."""
    assignment = get_object_or_404(
        PatientQuizAssignment, patient=request.patient, quiz_id=quiz_id
    )

    ok, error = _check_available(assignment)
    if not ok:
        return error

    quiz = assignment.quiz
    questions = quiz.questions.select_related('audio_file').all()
    return 200, {
        'id': quiz.id,
        'title': quiz.title,
        'description': quiz.description,
        'questions': [
            {
                'id': q.id,
                'audio_file_id': q.audio_file_id,
                'text': q.text,
                'options': q.options,
                'order': q.order,
            }
            for q in questions
        ],
        'audio_file_ids': list(quiz.audio_files.values_list('id', flat=True)),
    }


@router.get('/{quiz_id}/audio', response={200: list[AudioFileSchema], 403: ResultConfirmationSchema})
def get_quiz_audio_files(request, quiz_id: int):
    """Список аудио-файлов. Недоступные тесты → 403."""
    assignment = get_object_or_404(
        PatientQuizAssignment, patient=request.patient, quiz_id=quiz_id
    )

    ok, error = _check_available(assignment)
    if not ok:
        return error

    quiz = get_object_or_404(Quiz, id=quiz_id)
    audio_ids = set()
    audio_ids.update(quiz.audio_files.values_list('id', flat=True))
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
            'duration_seconds': af.duration_seconds,
            'uploaded_at': af.uploaded_at,
        }
        for af in audio_files
    ]


@router.post('/{quiz_id}/submit', response={200: ResultConfirmationSchema, 403: ResultConfirmationSchema})
def submit_quiz_result(request, quiz_id: int, payload: SubmitResultSchema):
    """Отправить ответы на квиз. Проверяет доступность и повторную отправку."""
    assignment = get_object_or_404(
        PatientQuizAssignment, patient=request.patient, quiz_id=quiz_id
    )

    if assignment.status == PatientQuizAssignment.Status.COMPLETED:
        return 403, {'status': 'error', 'message': 'Тест уже пройден, повторная отправка невозможна.'}

    ok, error = _check_available(assignment)
    if not ok:
        return error

    questions = {q.id: q.correct_answer for q in assignment.quiz.questions.all()}
    score = sum(
        1 for a in payload.answers
        if questions.get(a.question_id) == a.answer
    )

    QuizResult.objects.create(
        assignment=assignment,
        answers=[a.dict() for a in payload.answers],
        score=score,
    )

    assignment.status = PatientQuizAssignment.Status.COMPLETED
    assignment.completed_at = timezone.now()
    assignment.save()

    return 200, {'status': 'ok', 'message': 'Результаты успешно загружены на сервер.'}
