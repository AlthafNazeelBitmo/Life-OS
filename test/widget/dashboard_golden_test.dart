@Tags(<String>['golden'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/core/cache/key_value_store.dart';
import 'package:lifeos/core/di/core_providers.dart';
import 'package:lifeos/core/security/secure_store.dart';
import 'package:lifeos/core/theme/app_spacing.dart';
import 'package:lifeos/core/theme/app_theme.dart';
import 'package:lifeos/core/widgets/app_backdrop.dart';
import 'package:lifeos/domain/entities/calendar_event.dart';
import 'package:lifeos/domain/entities/goal.dart';
import 'package:lifeos/domain/entities/habit.dart';
import 'package:lifeos/domain/entities/health_metric.dart';
import 'package:lifeos/domain/entities/insight.dart';
import 'package:lifeos/domain/entities/mood_entry.dart';
import 'package:lifeos/domain/entities/task.dart';
import 'package:lifeos/domain/repositories/habit_repository.dart';
import 'package:lifeos/features/dashboard/presentation/widgets/dashboard_cards.dart';
import 'package:lifeos/services/analytics/life_score_service.dart';

/// Renders the dashboard card stack to a PNG.
///
/// Design reference as much as regression guard: the layout suite proves
/// nothing overflows, these show what it actually looks like in both themes.
///
/// Golden output depends on the host's font rasterisation, so this is tagged
/// and excluded from CI — run `flutter test --update-goldens
/// test/widget/dashboard_golden_test.dart` locally to refresh it.
void main() {
  setUpAll(() async {
    const path =
        '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf';
    if (!File(path).existsSync()) return;
    final bytes = File(path).readAsBytesSync();
    for (final family in <String>['Roboto', 'Inter']) {
      final loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  });

  final now = DateTime(2026, 7, 27, 8, 30);

  Widget cards() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const BriefingCard(
            summary: 'Two deadlines land today and the planning review moved '
                'to 10:00. Your focus scores have been highest before noon '
                'this week.',
          ),
          Gap.h16,
          MoodCard(
            mood: MoodEntry(
              id: 'm',
              recordedAt: now,
              dayKey: '2026-07-27',
              happiness: 8,
              energy: 7,
              stress: 3,
            ),
          ),
          Gap.h16,
          HabitRingCard(
            completion: 0.5,
            habits: <HabitWithProgress>[
              HabitWithProgress(
                habit: Habit(
                  id: 'h1',
                  name: 'Morning walk',
                  createdAt: now,
                  emoji: '🚶',
                ),
                loggedAmount: 1,
                streak: 12,
              ),
              HabitWithProgress(
                habit: Habit(
                  id: 'h2',
                  name: 'Read before bed',
                  createdAt: now,
                  emoji: '📚',
                ),
                loggedAmount: 0,
                streak: 4,
              ),
            ],
          ),
          Gap.h16,
          TasksCard(
            tasks: <Task>[
              Task(
                id: 't1',
                title: 'Reply to the planning thread',
                createdAt: now,
                dueAt: now.subtract(const Duration(hours: 2)),
                priority: TaskPriority.urgent,
                aiReason: 'Overdue and blocking two people',
              ),
              Task(id: 't2', title: 'Book the dentist', createdAt: now),
            ],
          ),
          Gap.h16,
          UpcomingCard(
            events: <CalendarEvent>[
              CalendarEvent(
                id: 'e1',
                title: 'Quarterly planning review',
                start: now.add(const Duration(hours: 2)),
                end: now.add(const Duration(hours: 3)),
                createdAt: now,
                location: 'Room 4',
              ),
            ],
          ),
          Gap.h16,
          const MoneyCard(spentTodayMinor: 2450),
          Gap.h16,
          const HealthCard(
            summary: DailyHealthSummary(
              dayKey: '2026-07-27',
              values: <HealthKind, double>{
                HealthKind.sleep: 7.5,
                HealthKind.water: 6,
                HealthKind.exercise: 45,
                HealthKind.screenTime: 3.25,
              },
            ),
          ),
          Gap.h16,
          LifeScoreCard(
            journalStreak: 14,
            goals: <Goal>[
              Goal(
                id: 'g1',
                title: 'Run a half marathon',
                createdAt: now,
                targetDate: now.add(const Duration(days: 60)),
                manualProgress: 0.45,
              ),
            ],
          ),
        ],
      );

  for (final brightness in Brightness.values) {
    testWidgets('dashboard cards render in ${brightness.name}', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 1900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
            secureStoreProvider.overrideWithValue(InMemorySecureStore()),
            lifeScoreProvider.overrideWith(
              (ref) async => LifeScore(
                computedAt: now,
                habits: 72,
                health: 64,
                finances: 81,
                productivity: 58,
                mood: 70,
                missingPillars: const <String>['Finances'],
              ),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: brightness == Brightness.light
                ? AppTheme.light()
                : AppTheme.dark(),
            home: AppBackdrop(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Padding(padding: Insets.page, child: cards()),
              ),
            ),
          ),
        ),
      );

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      await expectLater(
        find.byType(AppBackdrop),
        matchesGoldenFile('goldens/dashboard_${brightness.name}.png'),
      );
    });
  }
}
