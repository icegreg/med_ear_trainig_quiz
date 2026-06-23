import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  Future<void> _openPinSetup() async {
    await context.push('/pin-setup');
    if (mounted) setState(() {});
  }

  Future<void> _removePin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить код доступа?'),
        content: const Text(
          'Вход в приложение снова будет только по логину и паролю.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(storageProvider).clearPin();
    if (mounted) setState(() {});
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

          if (storage.isLoggedIn) ...[
            const Divider(height: 32),
            Text('Безопасность', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            if (storage.hasPin) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.pin_outlined),
                title: const Text('Изменить код доступа'),
                onTap: _openPinSetup,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.no_encryption_gmailerrorred_outlined,
                    color: theme.colorScheme.error),
                title: Text('Удалить код доступа',
                    style: TextStyle(color: theme.colorScheme.error)),
                onTap: _removePin,
              ),
            ] else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: const Text('Создать код быстрого входа'),
                subtitle: const Text('Вход по 4-значному коду вместо пароля'),
                onTap: _openPinSetup,
              ),
          ],

          const Divider(height: 32),
          Text('Подключение', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('Сборка: $kFlavor',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('По умолчанию: $kDefaultApiBaseUrl',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextField(
            controller: _apiUrlController,
            decoration: InputDecoration(
              labelText: 'API URL',
              suffixIcon: IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'Сохранить',
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: const Text('Сбросить на дефолт'),
              onPressed: () async {
                await storage.resetApiBaseUrl();
                _apiUrlController.text = kDefaultApiBaseUrl;
                ref.read(apiClientProvider).updateBaseUrl(kDefaultApiBaseUrl);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Сброшено на $kDefaultApiBaseUrl')),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
