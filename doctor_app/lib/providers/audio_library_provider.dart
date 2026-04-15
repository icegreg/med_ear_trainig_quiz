import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/audio_category.dart';
import '../models/audio_file.dart';
import 'auth_provider.dart';

final categoriesProvider = FutureProvider<List<AudioCategory>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.listCategories();
  return data.map((e) => AudioCategory.fromJson(e)).toList();
});

final selectedCategoryProvider = StateProvider<int?>((ref) => null);

final audioFilesProvider = FutureProvider<List<AudioFile>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final categoryId = ref.watch(selectedCategoryProvider);
  final data = await api.listAudio(categoryId: categoryId);
  return data.map((e) => AudioFile.fromJson(e)).toList();
});

final allAudioFilesProvider = FutureProvider<List<AudioFile>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.listAudio();
  return data.map((e) => AudioFile.fromJson(e)).toList();
});
