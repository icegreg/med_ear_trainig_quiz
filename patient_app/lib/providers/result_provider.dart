import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/quiz_result.dart';

final resultListProvider = FutureProvider<List<QuizResult>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getMyResults();
  return data.map((r) => QuizResult.fromJson(r)).toList();
});
