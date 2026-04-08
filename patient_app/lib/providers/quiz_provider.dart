import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/audio_file.dart';
import '../models/quiz.dart';

final quizListProvider = FutureProvider<List<QuizListItem>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getMyQuizzes();
  return data.map((q) => QuizListItem.fromJson(q)).toList();
});

final quizDetailProvider =
    FutureProvider.family<QuizDetail, int>((ref, quizId) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getQuizDetail(quizId);
  return QuizDetail.fromJson(data);
});

final quizAudioProvider =
    FutureProvider.family<List<AudioFile>, int>((ref, quizId) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getQuizAudio(quizId);
  return data.map((a) => AudioFile.fromJson(a)).toList();
});
