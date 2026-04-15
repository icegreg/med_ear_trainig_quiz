import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/patient.dart';
import 'auth_provider.dart';

final patientsProvider = FutureProvider<List<Patient>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getPatients();
  return data.map((e) => Patient.fromJson(e)).toList();
});
