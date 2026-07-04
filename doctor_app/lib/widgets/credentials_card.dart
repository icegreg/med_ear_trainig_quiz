import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/credentials_pdf.dart';

/// Показывает карточку с учётными данными пациента (plaintext).
/// Используется после создания пациента и после сброса пароля.
///
/// NB: кнопка «Скачать PDF» временно отключена (сам PDF-код в
/// core/credentials_pdf.dart сохранён). Чтобы вернуть — восстановить action
/// с ключом `creds_download`, вызывающий downloadCredentialsPdf().
Future<void> showCredentialsDialog(
  BuildContext context,
  PatientCredentials credentials, {
  String title = 'Данные для входа',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CredentialsDialog(credentials: credentials, title: title),
  );
}

class _CredentialsDialog extends StatelessWidget {
  final PatientCredentials credentials;
  final String title;

  const _CredentialsDialog({required this.credentials, required this.title});

  @override
  Widget build(BuildContext context) {
    final c = credentials;
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.fullName.isNotEmpty) ...[
              Text(c.fullName, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
            ],
            _CredRow(
              label: 'Логин',
              value: c.login,
              valueKey: const Key('creds_login'),
            ),
            const SizedBox(height: 8),
            _CredRow(
              label: 'Пароль',
              value: c.password,
              valueKey: const Key('creds_password'),
            ),
            const SizedBox(height: 16),
            Text(
              'Сохраните эти данные — пароль показывается один раз. '
              'Позже его можно только сбросить.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('creds_done'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}

class _CredRow extends StatelessWidget {
  final String label;
  final String value;
  final Key valueKey;

  const _CredRow({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: SelectableText(
            value,
            key: valueKey,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Копировать',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label скопирован'), duration: const Duration(seconds: 1)),
              );
            }
          },
        ),
      ],
    );
  }
}
