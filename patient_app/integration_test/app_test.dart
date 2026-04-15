/// Flutter integration E2E tests for Patient App.
///
/// Chrome headless: flutter test integration_test --device-id chrome
/// Chrome normal:   flutter test integration_test --device-id web-server
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patient_app/app.dart';
import 'package:patient_app/core/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    const secure = FlutterSecureStorage();
    storage = StorageService(prefs, secure);
    await secure.deleteAll();
    await prefs.clear();
  });

  group('Login flow', () {
    testWidgets('shows onboarding or login screen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageProvider.overrideWithValue(storage)],
          child: const HearingTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Should see either onboarding or login
      final hasOnboarding = find.text('Далее').evaluate().isNotEmpty;
      final hasLogin = find.text('Войти').evaluate().isNotEmpty;
      expect(hasOnboarding || hasLogin, isTrue);
    });

    testWidgets('can enter credentials on login screen', (tester) async {
      // Set onboarding completed
      await storage.setOnboardingCompleted();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageProvider.overrideWithValue(storage)],
          child: const HearingTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Should see login screen
      expect(find.text('Войти'), findsOneWidget);

      // Enter credentials
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));

      await tester.enterText(textFields.first, 'testpatient');
      await tester.enterText(textFields.last, 'patpass123');
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}
