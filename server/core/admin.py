from django import forms
from django.conf import settings
from django.contrib import admin, messages
from django.contrib.admin.helpers import ACTION_CHECKBOX_NAME
from django.contrib.auth.models import User
from django.http import FileResponse, Http404
from django.shortcuts import get_object_or_404, render
from django.urls import path, reverse
from django.utils.html import format_html
from django.utils.safestring import mark_safe

from . import client_logs, doctor_logs

# Версия бэкенда видна в шапке и на главной странице админки.
admin.site.site_header = f'TNOISE · бэкенд v{settings.BACKEND_VERSION}'
admin.site.site_title = 'TNOISE — администрирование'
admin.site.index_title = f'Администрирование (бэкенд v{settings.BACKEND_VERSION})'


def _status_class(code):
    """CSS-класс для подсветки HTTP-статуса в журнале."""
    if code is None:
        return 'unknown'
    if 200 <= code < 300:
        return 'ok'
    if 300 <= code < 400:
        return 'redirect'
    if 400 <= code < 500:
        return 'client-err'
    if 500 <= code < 600:
        return 'server-err'
    return 'unknown'


from .models import (
    AudioCategory,
    AudioFile,
    Clinic,
    DeviceToken,
    Doctor,
    Notification,
    Patient,
    PatientQuizAssignment,
    Quiz,
    QuizQuestion,
    QuizResult,
    Release,
)


# --- Миксин для soft delete моделей в админке ---

class SoftDeleteAdminMixin:
    """Миксин для админки моделей с soft delete."""

    def get_queryset(self, request):
        """Показываем все записи (включая удалённые)."""
        return self.model.all_objects.all()

    def delete_model(self, request, obj):
        """Одиночное удаление → soft delete."""
        obj.delete(user=request.user)

    def delete_queryset(self, request, queryset):
        """Массовое удаление → soft delete."""
        queryset.update(
            deleted_at=__import__('django.utils.timezone', fromlist=['now']).now(),
            deleted_by=request.user,
        )

    @admin.action(description='Восстановить выбранные')
    def restore_selected(self, request, queryset):
        count = queryset.update(deleted_at=None, deleted_by=None)
        messages.success(request, f'Восстановлено: {count}')


# --- Doctor ---

class DoctorCreationForm(forms.ModelForm):
    username = forms.CharField(label='Логин', max_length=150)
    email = forms.EmailField(label='Email')
    password = forms.CharField(label='Пароль', widget=forms.PasswordInput)

    class Meta:
        model = Doctor
        fields = ['last_name', 'first_name', 'patronymic', 'clinic', 'logging_enabled']

    def save(self, commit=True):
        user = User.objects.create_user(
            username=self.cleaned_data['username'],
            email=self.cleaned_data['email'],
            password=self.cleaned_data['password'],
            first_name=self.cleaned_data['first_name'],
            last_name=self.cleaned_data['last_name'],
        )
        doctor = super().save(commit=False)
        doctor.user = user
        if commit:
            doctor.save()
        return doctor


class DoctorChangeForm(forms.ModelForm):
    email = forms.EmailField(label='Email', required=False)

    class Meta:
        model = Doctor
        fields = ['last_name', 'first_name', 'patronymic', 'clinic', 'logging_enabled']

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if self.instance and self.instance.pk:
            self.fields['email'].initial = self.instance.user.email

    def save(self, commit=True):
        doctor = super().save(commit=commit)
        if self.cleaned_data.get('email'):
            doctor.user.email = self.cleaned_data['email']
            doctor.user.save(update_fields=['email'])
        return doctor


@admin.register(Doctor)
class DoctorAdmin(admin.ModelAdmin):
    list_display = ['__str__', 'clinic', 'email', 'logging_enabled', 'logs_link', 'created_at']
    list_filter = ['logging_enabled']
    search_fields = ['last_name', 'first_name', 'clinic']
    readonly_fields = ['id', 'created_at']

    def get_form(self, request, obj=None, **kwargs):
        if obj is None:
            kwargs['form'] = DoctorCreationForm
        else:
            kwargs['form'] = DoctorChangeForm
        return super().get_form(request, obj, **kwargs)

    @admin.display(description='Email')
    def email(self, obj):
        return obj.user.email

    @admin.display(description='Журнал действий')
    def logs_link(self, obj):
        url = reverse('admin:core_doctor_logs', args=[obj.pk])
        count = doctor_logs.line_count(obj.pk)
        if count == 0:
            return format_html('<a href="{}">пусто</a>', url)
        return format_html('<a href="{}">{} записей</a>', url, count)

    def get_urls(self):
        urls = super().get_urls()
        custom = [
            path(
                '<uuid:doctor_id>/logs/',
                self.admin_site.admin_view(self.view_logs),
                name='core_doctor_logs',
            ),
            path(
                '<uuid:doctor_id>/logs/download/',
                self.admin_site.admin_view(self.download_logs),
                name='core_doctor_logs_download',
            ),
        ]
        return custom + urls

    def view_logs(self, request, doctor_id):
        import json as _json
        doctor = get_object_or_404(Doctor, pk=doctor_id)
        max_lines = int(request.GET.get('lines', 500))
        max_lines = max(10, min(max_lines, 10000))

        total = doctor_logs.line_count(doctor.pk)
        raw_lines = doctor_logs.read_tail(doctor.pk, max_lines=max_lines)

        entries = []
        for idx, ln in enumerate(reversed(raw_lines)):
            try:
                data = _json.loads(ln)
            except Exception:
                entries.append({
                    'index': total - idx, 'ts': '?', 'action_label': '?',
                    'patient': ln[:120], 'detail': '', 'ip': '',
                    'full_json': ln,
                })
                continue
            entries.append({
                'index': total - idx,
                'ts': data.get('ts', '?'),
                'action': data.get('action', ''),
                'action_label': data.get('action_label', data.get('action', '?')),
                'patient': data.get('patient') or '—',
                'detail': data.get('detail', ''),
                'ip': data.get('ip', ''),
                'full_json': _json.dumps(data, ensure_ascii=False, indent=2),
            })

        context = {
            **self.admin_site.each_context(request),
            'title': f'Журнал действий — {doctor}',
            'doctor': doctor,
            'entries': entries,
            'line_count': total,
            'shown_count': len(entries),
            'file_size_kb': doctor_logs.file_size(doctor.pk) / 1024,
            'max_lines': max_lines,
            'opts': self.model._meta,
            'doctor_change_url': reverse('admin:core_doctor_change', args=[doctor.pk]),
            'download_url': reverse('admin:core_doctor_logs_download', args=[doctor.pk]),
        }
        return render(request, 'admin/core/doctor/action_logs.html', context)

    def download_logs(self, request, doctor_id):
        doctor = get_object_or_404(Doctor, pk=doctor_id)
        path_ = doctor_logs.log_path(doctor.pk)
        if not path_.exists():
            raise Http404('Журнал пуст')
        return FileResponse(
            open(path_, 'rb'),
            as_attachment=True,
            filename=f'doctor_{doctor.pk}_actions.jsonl',
        )


# --- Patient ---

class AssignedQuizInline(admin.TabularInline):
    """Назначенные (ожидающие) тесты пациента."""
    model = PatientQuizAssignment
    extra = 0
    verbose_name = 'Назначенный тест'
    verbose_name_plural = 'Назначенные тесты (ожидают прохождения)'
    fields = ['quiz', 'assigned_at', 'starts_at', 'ends_at']
    readonly_fields = ['assigned_at']
    raw_id_fields = ['quiz']

    def get_queryset(self, request):
        return super().get_queryset(request).filter(
            status=PatientQuizAssignment.Status.ASSIGNED,
        ).select_related('quiz')


class CompletedQuizInline(admin.TabularInline):
    """Пройденные тесты пациента."""
    model = PatientQuizAssignment
    extra = 0
    verbose_name = 'Пройденный тест'
    verbose_name_plural = 'Пройденные тесты'
    fields = ['quiz', 'assigned_at', 'completed_at']
    readonly_fields = ['quiz', 'assigned_at', 'completed_at']

    def get_queryset(self, request):
        return super().get_queryset(request).filter(
            status=PatientQuizAssignment.Status.COMPLETED,
        ).select_related('quiz')

    def has_add_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


class ReassignPatientsForm(forms.Form):
    """Промежуточная форма выбора нового врача для массового переназначения."""
    doctor = forms.ModelChoiceField(
        queryset=Doctor.objects.all(),
        label='Новый врач',
        empty_label='— выберите врача —',
    )


class TransferClinicForm(forms.Form):
    """Промежуточная форма выбора клиники для массового переноса пациентов."""
    clinic = forms.ModelChoiceField(
        queryset=Clinic.objects.all(),
        label='Клиника',
        empty_label='— выберите клинику —',
    )


@admin.register(Patient)
class PatientAdmin(admin.ModelAdmin):
    list_display = ['full_name_display', 'user', 'doctor', 'clinic', 'birth_date', 'assigned_count', 'completed_count', 'logging_enabled', 'logs_link', 'created_at']
    list_filter = ['doctor', 'clinic', 'logging_enabled']
    search_fields = ['last_name', 'first_name', 'patronymic', 'user__username']
    raw_id_fields = ['user', 'doctor', 'starting_sound']
    readonly_fields = ['logs_section']
    inlines = [AssignedQuizInline, CompletedQuizInline]
    actions = ['reassign_to_doctor', 'transfer_to_clinic']

    @admin.action(description='Переназначить выбранных пациентов другому врачу')
    def reassign_to_doctor(self, request, queryset):
        """Массово переназначить пациентов выбранному врачу.

        Показывает промежуточную страницу с выбором врача; по подтверждению
        переназначает и шлёт уведомление прежнему врачу каждого пациента
        (как в API /doctors/transfer-patient).
        """
        if 'apply' in request.POST:
            form = ReassignPatientsForm(request.POST)
            if form.is_valid():
                target = form.cleaned_data['doctor']
                reassigned = 0
                skipped = 0
                for patient in queryset.select_related('doctor', 'user'):
                    source = patient.doctor
                    if source and source.pk == target.pk:
                        skipped += 1
                        continue
                    patient.doctor = target
                    patient.save(update_fields=['doctor'])
                    reassigned += 1
                    if source is not None:
                        Notification.objects.create(
                            doctor=source,
                            type=Notification.Type.PATIENT_TRANSFERRED,
                            message=(
                                f'Пациент {patient.user.username} передан '
                                f'врачу {target}.'
                            ),
                            data={
                                'patient_id': patient.id,
                                'patient_username': patient.user.username,
                                'to_doctor_id': str(target.id),
                                'via': 'admin',
                            },
                        )
                msg = f'Переназначено пациентов: {reassigned} → {target}.'
                if skipped:
                    msg += f' Пропущено (уже у этого врача): {skipped}.'
                self.message_user(request, msg, messages.SUCCESS)
                return None  # вернуться к списку

            self.message_user(
                request, 'Выберите врача для переназначения.', messages.ERROR
            )

        form = ReassignPatientsForm()
        return render(
            request,
            'admin/core/patient/reassign.html',
            {
                **self.admin_site.each_context(request),
                'title': 'Переназначить пациентов',
                'opts': self.model._meta,
                'patients': queryset,
                'form': form,
                'action_checkbox_name': ACTION_CHECKBOX_NAME,
            },
        )

    @admin.action(description='Перенести выбранных пациентов в другую клинику')
    def transfer_to_clinic(self, request, queryset):
        """Массово перенести пациентов в выбранную клинику.

        Показывает промежуточную страницу с выбором клиники; по подтверждению
        обновляет привязку пациентов к клинике.
        """
        if 'apply' in request.POST:
            form = TransferClinicForm(request.POST)
            if form.is_valid():
                target = form.cleaned_data['clinic']
                moved = queryset.exclude(clinic=target).update(clinic=target)
                skipped = queryset.filter(clinic=target).count()
                msg = f'Перенесено пациентов в «{target}»: {moved}.'
                if skipped:
                    msg += f' Пропущено (уже в этой клинике): {skipped}.'
                self.message_user(request, msg, messages.SUCCESS)
                return None  # вернуться к списку

            self.message_user(
                request, 'Выберите клинику для переноса.', messages.ERROR
            )

        form = TransferClinicForm()
        return render(
            request,
            'admin/core/patient/transfer_clinic.html',
            {
                **self.admin_site.each_context(request),
                'title': 'Перенести пациентов в клинику',
                'opts': self.model._meta,
                'patients': queryset,
                'form': form,
                'action_checkbox_name': ACTION_CHECKBOX_NAME,
            },
        )

    def get_fields(self, request, obj=None):
        base = ['user', 'doctor', 'clinic', 'last_name', 'first_name', 'patronymic',
                'birth_date', 'starting_sound', 'logging_enabled']
        if obj:
            base.append('logs_section')
        return base

    @admin.display(description='Логи клиента')
    def logs_section(self, obj):
        if not obj or not obj.pk:
            return '—'
        url = reverse('admin:core_patient_logs', args=[obj.pk])
        count = client_logs.line_count(obj.pk)
        size_kb = client_logs.file_size(obj.pk) / 1024
        if count == 0:
            return mark_safe(
                '<span style="color:#888;">Журнал пуст. Логи появятся, когда '
                'у пациента включено логирование и приложение отправит запросы.</span>'
            )
        return format_html(
            '<a class="button" href="{}">Открыть журнал →</a>'
            '<span style="margin-left:12px;color:#555;">'
            'записей: <b>{}</b>, размер: <b>{} KB</b></span>',
            url, count, f'{size_kb:.1f}',
        )

    @admin.display(description='ФИО', ordering='last_name')
    def full_name_display(self, obj):
        return obj.full_name or '—'

    def get_queryset(self, request):
        from django.db.models import Count, Q
        return super().get_queryset(request).annotate(
            _assigned_count=Count(
                'quiz_assignments',
                filter=Q(quiz_assignments__status='assigned'),
            ),
            _completed_count=Count(
                'quiz_assignments',
                filter=Q(quiz_assignments__status='completed'),
            ),
        )

    @admin.display(description='Назначено', ordering='_assigned_count')
    def assigned_count(self, obj):
        return obj._assigned_count

    @admin.display(description='Пройдено', ordering='_completed_count')
    def completed_count(self, obj):
        return obj._completed_count

    @admin.display(description='Логи')
    def logs_link(self, obj):
        url = reverse('admin:core_patient_logs', args=[obj.pk])
        size = client_logs.file_size(obj.pk)
        if size == 0:
            return format_html('<a href="{}">пусто</a>', url)
        kb = size / 1024
        return format_html('<a href="{}">{} KB</a>', url, f'{kb:.1f}')

    def get_urls(self):
        urls = super().get_urls()
        custom = [
            path(
                '<int:patient_id>/logs/',
                self.admin_site.admin_view(self.view_logs),
                name='core_patient_logs',
            ),
            path(
                '<int:patient_id>/logs/download/',
                self.admin_site.admin_view(self.download_logs),
                name='core_patient_logs_download',
            ),
        ]
        return custom + urls

    def view_logs(self, request, patient_id):
        patient = get_object_or_404(Patient, pk=patient_id)
        max_lines = int(request.GET.get('lines', 500))
        max_lines = max(10, min(max_lines, 10000))

        import json as _json
        total = client_logs.line_count(patient.pk)
        raw_lines = client_logs.read_tail(patient.pk, max_lines=max_lines)

        entries = []
        # Самые свежие сверху
        for idx, ln in enumerate(reversed(raw_lines)):
            try:
                data = _json.loads(ln)
            except Exception:
                entries.append({
                    'index': total - idx,
                    'client_ts': '?',
                    'method': '?',
                    'path': ln[:120],
                    'status_code': None,
                    'status_class': 'unknown',
                    'duration_ms': None,
                    'full_json': ln,
                    'parse_error': True,
                })
                continue
            status = data.get('status_code')
            entries.append({
                'index': total - idx,
                'client_ts': data.get('client_ts', '?'),
                'method': data.get('method', '?'),
                'path': data.get('path', '?'),
                'status_code': status,
                'status_class': _status_class(status),
                'duration_ms': data.get('duration_ms'),
                'error_message': data.get('error_message'),
                'full_json': _json.dumps(data, ensure_ascii=False, indent=2),
                'parse_error': False,
            })

        context = {
            **self.admin_site.each_context(request),
            'title': f'Логи клиента — {patient}',
            'patient': patient,
            'entries': entries,
            'line_count': total,
            'shown_count': len(entries),
            'file_size_kb': client_logs.file_size(patient.pk) / 1024,
            'max_lines': max_lines,
            'opts': self.model._meta,
            'patient_change_url': reverse('admin:core_patient_change', args=[patient.pk]),
            'download_url': reverse('admin:core_patient_logs_download', args=[patient.pk]),
        }
        return render(request, 'admin/core/patient/client_logs.html', context)

    def download_logs(self, request, patient_id):
        patient = get_object_or_404(Patient, pk=patient_id)
        path = client_logs.log_path(patient.pk)
        if not path.exists():
            raise Http404('Файл логов пуст')
        return FileResponse(
            open(path, 'rb'),
            as_attachment=True,
            filename=f'patient_{patient.pk}_logs.jsonl',
        )


# --- Clinic ---

@admin.register(Clinic)
class ClinicAdmin(admin.ModelAdmin):
    list_display = ['name', 'abbreviation', 'address', 'patient_count', 'created_at']
    search_fields = ['name', 'abbreviation', 'address']

    def get_queryset(self, request):
        from django.db.models import Count
        return super().get_queryset(request).annotate(
            _patient_count=Count('patients'),
        )

    @admin.display(description='Пациентов', ordering='_patient_count')
    def patient_count(self, obj):
        return obj._patient_count


# --- AudioCategory ---

@admin.register(AudioCategory)
class AudioCategoryAdmin(admin.ModelAdmin):
    list_display = ['name', 'parent', 'audio_count', 'created_at']
    search_fields = ['name']
    list_filter = ['parent']
    raw_id_fields = ['parent']

    def get_queryset(self, request):
        from django.db.models import Count
        return super().get_queryset(request).annotate(
            _audio_count=Count('audio_files'),
        )

    @admin.display(description='Аудио-файлов', ordering='_audio_count')
    def audio_count(self, obj):
        return obj._audio_count


# --- AudioFile (soft delete) ---

@admin.register(AudioFile)
class AudioFileAdmin(SoftDeleteAdminMixin, admin.ModelAdmin):
    list_display = ['title', 'category', 'duration_seconds', 'uploaded_at', 'is_deleted_display', 'deleted_at', 'deleted_by']
    search_fields = ['title']
    list_filter = ['category', 'deleted_at']
    readonly_fields = ['deleted_at', 'deleted_by']
    raw_id_fields = ['category']
    actions = ['restore_selected']

    @admin.display(description='Удалён', boolean=True)
    def is_deleted_display(self, obj):
        return obj.is_deleted


# --- Quiz ---

class QuizQuestionInline(admin.TabularInline):
    model = QuizQuestion
    extra = 1
    raw_id_fields = ['audio_file']


@admin.register(Quiz)
class QuizAdmin(admin.ModelAdmin):
    list_display = ['title', 'created_at', 'updated_at']
    search_fields = ['title']
    filter_horizontal = ['audio_files']
    inlines = [QuizQuestionInline]


# --- PatientQuizAssignment ---

@admin.register(PatientQuizAssignment)
class PatientQuizAssignmentAdmin(admin.ModelAdmin):
    list_display = ['patient', 'quiz', 'status', 'assigned_at', 'starts_at', 'ends_at', 'completed_at']
    list_filter = ['status']
    raw_id_fields = ['patient', 'quiz']


# --- QuizResult (soft delete) ---

@admin.register(QuizResult)
class QuizResultAdmin(SoftDeleteAdminMixin, admin.ModelAdmin):
    list_display = ['assignment', 'score', 'submitted_at', 'is_deleted_display', 'deleted_at', 'deleted_by']
    raw_id_fields = ['assignment']
    readonly_fields = ['answers', 'score', 'submitted_at', 'deleted_at', 'deleted_by']
    list_filter = ['deleted_at']
    actions = ['restore_selected', 'hard_delete_selected']

    @admin.display(description='Удалён', boolean=True)
    def is_deleted_display(self, obj):
        return obj.is_deleted

    @admin.action(description='ФИЗИЧЕСКИ удалить выбранные (необратимо)')
    def hard_delete_selected(self, request, queryset):
        count = queryset.count()
        queryset.hard_delete()
        messages.warning(request, f'Физически удалено: {count}')


# --- DeviceToken ---

@admin.register(DeviceToken)
class DeviceTokenAdmin(admin.ModelAdmin):
    list_display = ['token_short', 'patient', 'is_active', 'created_at', 'last_used_at']
    list_filter = ['is_active']
    raw_id_fields = ['patient']
    readonly_fields = ['token', 'created_at', 'last_used_at']

    @admin.display(description='Token')
    def token_short(self, obj):
        return f'{obj.token[:8]}...'


# --- Notification ---

@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ['doctor', 'type', 'message_short', 'is_read', 'created_at']
    list_filter = ['type', 'is_read', 'doctor']
    readonly_fields = ['doctor', 'type', 'message', 'data', 'created_at']
    search_fields = ['message']

    @admin.display(description='Сообщение')
    def message_short(self, obj):
        return obj.message[:80] + '...' if len(obj.message) > 80 else obj.message


# --- Release (APK) ---

@admin.register(Release)
class ReleaseAdmin(admin.ModelAdmin):
    list_display = ['__str__', 'is_default', 'size_display', 'download_link', 'created_at']
    list_filter = ['is_default']
    search_fields = ['version_name']
    readonly_fields = ['size_display', 'created_at', 'download_link']
    actions = ['make_default']

    @admin.display(description='Размер')
    def size_display(self, obj):
        # file_size — property, выводится из файла.
        return f'{obj.file_size / (1024 * 1024):.1f} МБ' if obj.file_size else '—'

    @admin.display(description='Скачать')
    def download_link(self, obj):
        if not obj.apk:
            return '—'
        return format_html('<a href="{}" target="_blank">APK</a>', obj.apk.url)

    @admin.action(description='Сделать дефолтным (выберите один релиз)')
    def make_default(self, request, queryset):
        if queryset.count() != 1:
            messages.error(request, 'Выберите ровно один релиз для назначения дефолтным.')
            return
        release = queryset.first()
        release.set_default()
        messages.success(request, f'Дефолтный релиз: {release}')
