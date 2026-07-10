import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/credentials_pdf.dart';
import '../core/password_gen.dart';
import '../providers/auth_provider.dart';
import '../providers/patients_provider.dart';
import '../widgets/credentials_card.dart';

class AddPatientScreen extends ConsumerStatefulWidget {
  const AddPatientScreen({super.key});

  @override
  ConsumerState<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends ConsumerState<AddPatientScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _patronymicCtrl = TextEditingController();
  DateTime? _birthDate;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  /// Клиники (для селектора) и выбранная клиника.
  List<Map<String, dynamic>> _clinics = [];
  int? _clinicId;
  bool _loadingClinics = true;

  /// Врач вручную поправил логин — перестаём автогенерировать.
  bool _loginEdited = false;
  bool _generatingLogin = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _passwordCtrl.text = generatePassword();
    _loadClinics();
  }

  Future<void> _loadClinics() async {
    try {
      final clinics = await ref.read(apiClientProvider).listClinics();
      if (!mounted) return;
      setState(() {
        _clinics = clinics.cast<Map<String, dynamic>>();
        if (_clinics.isNotEmpty) {
          _clinicId = _clinics.first['id'] as int;
        }
        _loadingClinics = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingClinics = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _lastNameCtrl.dispose();
    _firstNameCtrl.dispose();
    _patronymicCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Дата рождения',
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
      _scheduleLoginGen();
    }
  }

  /// Дебаунс автогенерации логина при вводе ФИО.
  void _scheduleLoginGen() {
    if (_loginEdited) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _generateLogin);
  }

  Future<void> _generateLogin() async {
    final lastName = _lastNameCtrl.text.trim();
    if (lastName.isEmpty) return; // нечего генерировать
    setState(() => _generatingLogin = true);
    try {
      final login = await ref.read(apiClientProvider).suggestLogin(
            lastName: lastName,
            firstName: _firstNameCtrl.text.trim(),
            patronymic: _patronymicCtrl.text.trim(),
            birthDate: _birthDate,
            clinicId: _clinicId,
          );
      if (!mounted || _loginEdited) return;
      _usernameCtrl.text = login;
    } catch (_) {
      // Не критично: врач может ввести логин вручную.
    } finally {
      if (mounted) setState(() => _generatingLogin = false);
    }
  }

  void _regeneratePassword() {
    setState(() => _passwordCtrl.text = generatePassword());
  }

  Future<void> _submit() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Введите логин и пароль');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final result = await api.createPatient(
        username,
        password,
        clinicId: _clinicId,
        lastName: _lastNameCtrl.text.trim(),
        firstName: _firstNameCtrl.text.trim(),
        patronymic: _patronymicCtrl.text.trim(),
        birthDate: _birthDate,
      );
      ref.invalidate(patientsProvider);

      // Профиль врача для PDF (не блокируем показ карточки при ошибке).
      Map<String, dynamic>? profile;
      try {
        profile = await ref.read(doctorProfileProvider.future);
      } catch (_) {}

      if (!mounted) return;
      final creds = PatientCredentials(
        fullName: _composeFullName(),
        login: result['username'] as String,
        password: password,
        doctorName: profile == null ? null : _doctorName(profile),
        clinic: profile?['clinic'] as String?,
        generatedAt: DateTime.now(),
      );
      await showCredentialsDialog(context, creds, title: 'Пациент создан');
      if (mounted) context.go('/patients/${result['id']}');
    } on DioException catch (e) {
      setState(() {
        _error = (e.response?.data is Map)
            ? e.response!.data['message'] ?? 'Ошибка создания пациента'
            : 'Ошибка создания пациента';
      });
    } catch (e) {
      setState(() => _error = 'Ошибка создания пациента: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _composeFullName() => [
        _lastNameCtrl.text.trim(),
        _firstNameCtrl.text.trim(),
        _patronymicCtrl.text.trim(),
      ].where((s) => s.isNotEmpty).join(' ');

  static String _doctorName(Map<String, dynamic> p) => [
        p['last_name'],
        p['first_name'],
        p['patronymic'],
      ].where((s) => s != null && (s as String).isNotEmpty).join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый пациент')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('field_last_name'),
                  controller: _lastNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Фамилия',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _scheduleLoginGen(),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('field_first_name'),
                  controller: _firstNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _scheduleLoginGen(),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('field_patronymic'),
                  controller: _patronymicCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Отчество',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _scheduleLoginGen(),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickBirthDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Дата рождения',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      _birthDate == null
                          ? 'Не указана'
                          : _formatDate(_birthDate!),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_loadingClinics)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else if (_clinics.isNotEmpty)
                  DropdownButtonFormField<int>(
                    key: const Key('field_clinic'),
                    value: _clinicId,
                    decoration: const InputDecoration(
                      labelText: 'Клиника',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in _clinics)
                        DropdownMenuItem<int>(
                          value: c['id'] as int,
                          child: Text('${c['name']} (${c['abbreviation']})'),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _clinicId = value);
                      // Префикс логина зависит от клиники — перегенерируем.
                      if (!_loginEdited) _generateLogin();
                    },
                  ),
                const Divider(height: 32),
                TextField(
                  key: const Key('field_login'),
                  controller: _usernameCtrl,
                  onChanged: (_) => _loginEdited = true,
                  decoration: InputDecoration(
                    labelText: 'Логин',
                    helperText: 'Генерируется из ФИО, можно изменить',
                    border: const OutlineInputBorder(),
                    suffixIcon: _generatingLogin
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              height: 16, width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Сгенерировать логин',
                            onPressed: () {
                              _loginEdited = false;
                              _generateLogin();
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('field_password'),
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.autorenew),
                          tooltip: 'Сгенерировать пароль',
                          onPressed: _regeneratePassword,
                        ),
                        IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          tooltip: _obscurePassword
                              ? 'Показать пароль'
                              : 'Скрыть пароль',
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('btn_create'),
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Создать пациента'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
