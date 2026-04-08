from django import forms
from django.contrib import admin, messages
from django.contrib.auth.models import User

from .models import (
    AudioFile,
    DeviceToken,
    Doctor,
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
        fields = ['last_name', 'first_name', 'patronymic', 'clinic']

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
        fields = ['last_name', 'first_name', 'patronymic', 'clinic']

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
    list_display = ['__str__', 'clinic', 'email', 'created_at']
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

@admin.register(Patient)
class PatientAdmin(admin.ModelAdmin):
    list_display = ['user', 'doctor', 'created_at']
    list_filter = ['doctor']
    raw_id_fields = ['user', 'doctor']


# --- AudioFile (soft delete) ---

@admin.register(AudioFile)
class AudioFileAdmin(SoftDeleteAdminMixin, admin.ModelAdmin):
    list_display = ['title', 'duration_seconds', 'uploaded_at', 'is_deleted_display', 'deleted_at', 'deleted_by']
    search_fields = ['title']
    list_filter = ['deleted_at']
    readonly_fields = ['deleted_at', 'deleted_by']
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
