from uuid import UUID

from django.shortcuts import get_object_or_404
from ninja import Router

from ..models import Doctor, Patient, PatientQuizAssignment, QuizResult
from ..schemas import (
    DoctorSchema,
    PatientSchema,
    QuizResultSchema,
    TransferPatientSchema,
    TransferResultSchema,
)

router = Router()


@router.get('/me', response=DoctorSchema)
def get_doctor_profile(request):
    """Профиль текущего врача."""
    return request.doctor


@router.get('/me/patients', response=list[PatientSchema])
def get_my_patients(request):
    """Список пациентов текущего врача."""
    patients = request.doctor.patients.select_related('user').all()
    return [
        {
            'id': p.id,
            'username': p.user.username,
            'doctor_id': p.doctor_id,
            'created_at': p.created_at,
        }
        for p in patients
    ]


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

    return 200, {
        'status': 'ok',
        'message': f'Пациент передан врачу {target_doctor.id}.',
    }
