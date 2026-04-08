import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/patient.dart';

final patientProvider = FutureProvider<Patient>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getMyProfile();
  return Patient.fromJson(data);
});
