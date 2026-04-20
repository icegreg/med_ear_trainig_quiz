import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/audio_file.dart';
import '../models/quiz.dart';
import 'auth_provider.dart';

final quizzesProvider = FutureProvider<List<QuizSummary>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.listQuizzes();
  return data.map((e) => QuizSummary.fromJson(e)).toList();
});

final quizAudioProvider = FutureProvider.family<List<AudioFile>, int>((ref, quizId) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getQuizAudio(quizId);
  return data.map((e) => AudioFile.fromJson(e)).toList();
});
