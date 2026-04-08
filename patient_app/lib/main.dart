import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);

  runApp(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
      ],
      child: const PatientApp(),
    ),
  );
}
