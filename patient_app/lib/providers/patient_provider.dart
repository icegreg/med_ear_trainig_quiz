import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/log_buffer.dart';
import '../models/patient.dart';

final patientProvider = FutureProvider<Patient>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getMyProfile();
  final patient = Patient.fromJson(data);
  // Синхронизируем состояние буфера логов с тем, что сервер сказал про пациента.
  ref.read(logBufferProvider).setEnabled(patient.loggingEnabled);
  return patient;
});
