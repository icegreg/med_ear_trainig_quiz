/// Flutter integration E2E tests for Doctor App.
///
/// Chrome headless: flutter test integration_test --device-id chrome
/// Chrome normal:   flutter test integration_test --device-id web-server
library;

import 'package:doctor_app/app.dart';
import 'package:doctor_app/core/storage.dart';
import 'package:doctor_app/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;

  setUp(() async {
    storage = StorageService();
    await storage.init();
    await storage.clearTokens();
  });

  group('Login flow', () {
    testWidgets('shows login screen when not authenticated', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageProvider.overrideWithValue(storage)],
          child: const DoctorApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Should see login screen
      expect(find.text('Вход для врача'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Войти'), findsOneWidget);
    });

    testWidgets('login with wrong credentials shows error', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageProvider.overrideWithValue(storage)],
          child: const DoctorApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter wrong credentials
      await tester.enterText(find.byType(TextField).first, 'wrong');
      await tester.enterText(find.byType(TextField).last, 'wrong');
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Should still be on login screen (error shown)
      expect(find.text('Вход для врача'), findsOneWidget);
    });

    testWidgets('login with correct credentials navigates to dashboard', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageProvider.overrideWithValue(storage)],
          child: const DoctorApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter correct credentials
      await tester.enterText(find.byType(TextField).first, 'testdoctor');
      await tester.enterText(find.byType(TextField).last, 'docpass123');
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Should see dashboard
      expect(find.text('Главная'), findsOneWidget);
    });
  });

  group('Navigation', () {
    testWidgets('can navigate between sections', (tester) async {
      // Pre-auth
      storage = StorageService();
      await storage.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageProvider.overrideWithValue(storage)],
          child: const DoctorApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Login first
      await tester.enterText(find.byType(TextField).first, 'testdoctor');
      await tester.enterText(find.byType(TextField).last, 'docpass123');
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to Patients
      await tester.tap(find.text('Пациенты'));
      await tester.pumpAndSettle();
      expect(find.text('Пациенты'), findsWidgets);

      // Navigate to Audio
      await tester.tap(find.text('Аудио'));
      await tester.pumpAndSettle();
      expect(find.text('Библиотека звуков'), findsOneWidget);

      // Navigate to Tests
      await tester.tap(find.text('Тесты'));
      await tester.pumpAndSettle();
      expect(find.text('Тесты'), findsWidgets);

      // Navigate to Notifications
      await tester.tap(find.text('Уведомления'));
      await tester.pumpAndSettle();
      expect(find.text('Уведомления'), findsWidgets);
    });
  });
}
