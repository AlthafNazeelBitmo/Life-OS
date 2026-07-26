import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifeos/app.dart';
import 'package:lifeos/core/cache/key_value_store.dart';
import 'package:lifeos/core/di/core_providers.dart';
import 'package:lifeos/core/security/secure_store.dart';
import 'package:lifeos/core/settings/settings_controller.dart';
import 'package:lifeos/data/local/app_database.dart';
import 'package:drift/native.dart';

/// End-to-end passes over the flows a user actually performs on first run.
///
/// Everything is wired to in-memory storage, so the suite is hermetic: no
/// leftover database between runs and no dependency on a backend.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late KeyValueStore cache;

  Future<void> launch(WidgetTester tester, {bool onboarded = true}) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cache = InMemoryKeyValueStore();

    final container = ProviderContainer(
      overrides: <Override>[
        keyValueStoreProvider.overrideWithValue(cache),
        secureStoreProvider.overrideWithValue(InMemorySecureStore()),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);

    if (onboarded) {
      await container.read(settingsProvider.notifier).completeOnboarding();
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LifeOsApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  testWidgets('a first-time user is taken through onboarding', (tester) async {
    await launch(tester, onboarded: false);

    expect(find.text('One place for your whole life'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Patterns, not just records'), findsOneWidget);
  });

  testWidgets('a local account reaches the dashboard', (tester) async {
    await launch(tester);

    // Onboarding is done, so the router lands on sign-in.
    expect(find.text('Use on this device only'), findsOneWidget);

    await tester.tap(find.text('Use on this device only'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('Good'), findsAtLeastNWidgets(1));
    expect(find.text('Journal'), findsAtLeastNWidgets(1));
  });

  testWidgets('quick-adding a task shows it on the dashboard', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Use on this device only'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('Task'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Buy oat milk');
    await tester.tap(find.text('Add to today'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Buy oat milk'), findsAtLeastNWidgets(1));
  });

  testWidgets('writing a journal entry persists it to the feed',
      (tester) async {
    await launch(tester);
    await tester.tap(find.text('Use on this device only'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('Journal').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Write'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'What happened today?'),
      'A quiet morning and a long walk by the river.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('quiet morning'), findsAtLeastNWidgets(1));
  });

  testWidgets('the assistant works with no AI provider configured',
      (tester) async {
    await launch(tester);
    await tester.tap(find.text('Use on this device only'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.byTooltip('Ask the assistant · hold to speak'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The on-device banner is the promise that the app is useful without a key.
    expect(find.textContaining('On-device mode'), findsOneWidget);
    expect(find.text('Ask about your life'), findsOneWidget);
  });

  testWidgets('theme changes apply immediately', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Use on this device only'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp).first);
    expect(app.themeMode, ThemeMode.dark);
  });
}
