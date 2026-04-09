import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../core/storage.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _apiUrlController;

  @override
  void initState() {
    super.initState();
    final storage = ref.read(storageProvider);
    _apiUrlController = TextEditingController(text: storage.apiBaseUrl);
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(storageProvider);
    final isDark = ref.watch(darkModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Тема
          Text('Оформление', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Тёмная тема'),
            secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
            value: isDark,
            onChanged: (_) => ref.read(darkModeProvider.notifier).toggle(),
          ),

          const Divider(height: 32),

          // Батарея
          Text('Тестирование', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          Text('Минимальный заряд батареи: '
              '${storage.batteryThreshold.round()}%'),
          Slider(
            value: storage.batteryThreshold,
            min: 5,
            max: 50,
            divisions: 9,
            label: '${storage.batteryThreshold.round()}%',
            onChanged: (v) async {
              await storage.setBatteryThreshold(v);
              setState(() {});
            },
          ),

          const SizedBox(height: 8),
          Text('Уровень громкости: '
              '${(storage.volumeLevel * 100).round()}%'),
          Slider(
            value: storage.volumeLevel,
            min: 0.1,
            max: 1.0,
            divisions: 9,
            label: '${(storage.volumeLevel * 100).round()}%',
            onChanged: (v) async {
              await storage.setVolumeLevel(v);
              setState(() {});
            },
          ),

          // API URL — только для dev/preprod
          if (kFlavor != 'prod') ...[
            const Divider(height: 32),
            Text('Подключение', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Сборка: $kFlavor',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: _apiUrlController,
              decoration: InputDecoration(
                labelText: 'API URL',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () async {
                    final url = _apiUrlController.text.trim();
                    if (url.isNotEmpty) {
                      await storage.setApiBaseUrl(url);
                      ref.read(apiClientProvider).updateBaseUrl(url);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('URL сохранён')),
                        );
                      }
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await storage.resetApiBaseUrl();
                _apiUrlController.text = kDefaultApiBaseUrl;
                ref.read(apiClientProvider).updateBaseUrl(kDefaultApiBaseUrl);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Сброшено на $kDefaultApiBaseUrl')),
                  );
                }
              },
            child: const Text('Сбросить на дефолт'),
          ),
          ],
        ],
      ),
    );
  }
}
