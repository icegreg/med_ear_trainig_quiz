import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:web/web.dart' as web;

/// Учётные данные пациента, показываемые врачу один раз (plaintext).
class PatientCredentials {
  final String fullName;
  final String login;
  final String password;
  final String? doctorName;
  final String? clinic;
  final DateTime generatedAt;

  PatientCredentials({
    required this.fullName,
    required this.login,
    required this.password,
    this.doctorName,
    this.clinic,
    required this.generatedAt,
  });
}

/// Собирает PDF с данными для входа пациента (кириллица через DejaVu Sans).
Future<Uint8List> buildCredentialsPdf(PatientCredentials c) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(c.generatedAt);

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      build: (context) {
        pw.Widget row(String label, String value, {bool mono = false}) {
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 110,
                  child: pw.Text(label,
                      style: pw.TextStyle(color: PdfColors.grey700)),
                ),
                pw.Expanded(
                  child: pw.Text(
                    value,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: mono ? 16 : 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Данные для входа пациента',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            if (c.clinic != null && c.clinic!.isNotEmpty)
              pw.Text(c.clinic!, style: pw.TextStyle(color: PdfColors.grey700)),
            if (c.doctorName != null && c.doctorName!.isNotEmpty)
              pw.Text('Врач: ${c.doctorName!}',
                  style: pw.TextStyle(color: PdfColors.grey700)),
            pw.SizedBox(height: 16),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  row('Пациент', c.fullName.isEmpty ? '—' : c.fullName),
                  pw.Divider(color: PdfColors.grey300),
                  row('Логин', c.login, mono: true),
                  row('Пароль', c.password, mono: true),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Сохраните эти данные. Пароль показывается один раз — '
              'после закрытия его можно только сбросить.',
              style: pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
            ),
            pw.Spacer(),
            pw.Text('Сформировано: $dateStr',
                style: pw.TextStyle(color: PdfColors.grey500, fontSize: 9)),
          ],
        );
      },
    ),
  );
  return doc.save();
}

/// Триггерит скачивание [bytes] в браузере как файл [filename].
void downloadBytes(Uint8List bytes, String filename,
    {String mime = 'application/pdf'}) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

/// Собирает и скачивает PDF с данными пациента.
Future<void> downloadCredentialsPdf(PatientCredentials c) async {
  final bytes = await buildCredentialsPdf(c);
  final safeLogin = c.login.isEmpty ? 'patient' : c.login;
  downloadBytes(bytes, 'creds_$safeLogin.pdf');
}
