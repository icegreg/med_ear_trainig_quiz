from django import forms
from django.conf import settings
from django.contrib import admin, messages
from django.contrib.auth.models import User
from django.http import FileResponse, Http404
from django.shortcuts import get_object_or_404, render
from django.urls import path, reverse
from django.utils.html import format_html
from django.utils.safestring import mark_safe

from . import client_logs

# Версия бэкенда видна в шапке и на главной странице админки.
admin.site.site_header = f'Тест слуха · бэкенд v{settings.BACKEND_VERSION}'
admin.site.site_title = 'Тест слуха — администрирование'
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
    DeviceToken,
    Doctor,
    Notification,
    Patient,
    PatientQuizAssignment,
    Quiz,
    QuizQuestion,
    QuizResult,
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
    list_display = ['__str__', 'clinic', 'email', 'logging_enabled', 'created_at']
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


@admin.register(Patient)
class PatientAdmin(admin.ModelAdmin):
    list_display = ['full_name_display', 'user', 'doctor', 'birth_date', 'assigned_count', 'completed_count', 'logging_enabled', 'logs_link', 'created_at']
    list_filter = ['doctor', 'logging_enabled']
    search_fields = ['last_name', 'first_name', 'patronymic', 'user__username']
    raw_id_fields = ['user', 'doctor', 'starting_sound']
    readonly_fields = ['logs_section']
    inlines = [AssignedQuizInline, CompletedQuizInline]

    def get_fields(self, request, obj=None):
        base = ['user', 'doctor', 'last_name', 'first_name', 'patronymic',
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
