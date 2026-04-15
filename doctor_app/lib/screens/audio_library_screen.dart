import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/audio_category.dart';
import '../models/audio_file.dart';
import '../providers/auth_provider.dart';
import '../providers/audio_library_provider.dart';

class AudioLibraryScreen extends ConsumerStatefulWidget {
  const AudioLibraryScreen({super.key});

  @override
  ConsumerState<AudioLibraryScreen> createState() => _AudioLibraryScreenState();
}

class _AudioLibraryScreenState extends ConsumerState<AudioLibraryScreen> {
  final _player = AudioPlayer();
  int? _playingId;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(categoriesProvider);
    ref.invalidate(audioFilesProvider);
  }

  Future<void> _playAudio(AudioFile audio) async {
    if (_playingId == audio.id) {
      await _player.stop();
      setState(() => _playingId = null);
      return;
    }
    try {
      await _player.setUrl(audio.fileUrl);
      setState(() => _playingId = audio.id);
      await _player.play();
      if (mounted) setState(() => _playingId = null);
    } catch (_) {
      if (mounted) setState(() => _playingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final audioAsync = ref.watch(audioFilesProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Библиотека звуков'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'Новая категория',
            onPressed: () => _showCreateCategoryDialog(context),
          ),
        ],
      ),
      body: Row(
        children: [
          // Categories panel
          SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Категории', style: Theme.of(context).textTheme.titleSmall),
                ),
                Expanded(
                  child: categoriesAsync.when(
                    data: (categories) {
                      return ListView(
                        children: [
                          ListTile(
                            title: const Text('Все'),
                            selected: selectedCategory == null,
                            onTap: () => ref.read(selectedCategoryProvider.notifier).state = null,
                          ),
                          ...categories.expand((c) => _buildCategoryTiles(c, 0)),
                        ],
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Ошибка: $e')),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Audio files panel
          Expanded(
            child: audioAsync.when(
              data: (audioFiles) {
                if (audioFiles.isEmpty) {
                  return const Center(child: Text('Нет аудио-файлов'));
                }
                return ListView.builder(
                  itemCount: audioFiles.length,
                  itemBuilder: (context, i) {
                    final audio = audioFiles[i];
                    final isPlaying = _playingId == audio.id;
                    return ListTile(
                      leading: IconButton(
                        icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                        onPressed: () => _playAudio(audio),
                      ),
                      title: Text(audio.title),
                      subtitle: Text(audio.durationSeconds != null
                          ? '${audio.durationSeconds} сек'
                          : 'Длительность неизвестна'),
                      trailing: PopupMenuButton(
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'move', child: Text('Переместить')),
                        ],
                        onSelected: (v) {
                          if (v == 'move') _showMoveDialog(context, audio);
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Ошибка: $e')),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCategoryTiles(AudioCategory cat, int depth) {
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final tiles = <Widget>[
      ListTile(
        contentPadding: EdgeInsets.only(left: 16.0 + depth * 24),
        title: Text(cat.name),
        selected: selectedCategory == cat.id,
        onTap: () => ref.read(selectedCategoryProvider.notifier).state = cat.id,
        trailing: PopupMenuButton(
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'rename', child: Text('Переименовать')),
            const PopupMenuItem(value: 'add_sub', child: Text('Подкатегория')),
            const PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
          onSelected: (v) {
            switch (v) {
              case 'rename':
                _showRenameCategoryDialog(context, cat);
              case 'add_sub':
                _showCreateCategoryDialog(context, parentId: cat.id);
              case 'delete':
                _showDeleteCategoryDialog(context, cat);
            }
          },
        ),
      ),
    ];
    for (final child in cat.children) {
      tiles.addAll(_buildCategoryTiles(child, depth + 1));
    }
    return tiles;
  }

  void _showCreateCategoryDialog(BuildContext context, {int? parentId}) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(parentId != null ? 'Новая подкатегория' : 'Новая категория'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              final api = ref.read(apiClientProvider);
              await api.createCategory(ctrl.text.trim(), parentId: parentId);
              _refresh();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  void _showRenameCategoryDialog(BuildContext context, AudioCategory cat) {
    final ctrl = TextEditingController(text: cat.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              final api = ref.read(apiClientProvider);
              try {
                await api.renameCategory(cat.id, ctrl.text.trim());
                _refresh();
              } on DioException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text((e.response?.data is Map)
                        ? e.response!.data['message'] : 'Ошибка'),
                  ));
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _showDeleteCategoryDialog(BuildContext context, AudioCategory cat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить категорию?'),
        content: Text('Файлы будут перемещены в корневую категорию.\nУдалить "${cat.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              final api = ref.read(apiClientProvider);
              try {
                await api.deleteCategory(cat.id);
                _refresh();
                ref.read(selectedCategoryProvider.notifier).state = null;
              } on DioException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text((e.response?.data is Map)
                        ? e.response!.data['message'] : 'Ошибка'),
                  ));
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _showMoveDialog(BuildContext context, AudioFile audio) {
    final categoriesAsync = ref.read(categoriesProvider);
    categoriesAsync.whenData((categories) {
      final allCats = <AudioCategory>[];
      void flatten(List<AudioCategory> list) {
        for (final c in list) {
          allCats.add(c);
          flatten(c.children);
        }
      }
      flatten(categories);

      int? selected = audio.categoryId;
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Переместить в категорию'),
            content: DropdownButtonFormField<int>(
              value: selected,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: allCats.map((c) => DropdownMenuItem(
                value: c.id,
                child: Text(c.name),
              )).toList(),
              onChanged: (v) => setDialogState(() => selected = v),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
              FilledButton(
                onPressed: selected == null ? null : () async {
                  final api = ref.read(apiClientProvider);
                  await api.moveAudio(audio.id, selected!);
                  _refresh();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Переместить'),
              ),
            ],
          ),
        ),
      );
    });
  }
}
