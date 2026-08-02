import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/core/cache/key_value_store.dart';
import 'package:lifeos/core/di/core_providers.dart';
import 'package:lifeos/core/security/secure_store.dart';
import 'package:lifeos/core/theme/app_theme.dart';
import 'package:lifeos/core/widgets/chip_strip.dart';
import 'package:lifeos/core/widgets/glass_card.dart';
import 'package:lifeos/core/widgets/progress_ring.dart';
import 'package:lifeos/core/widgets/section_header.dart';
import 'package:lifeos/core/widgets/stat_tile.dart';
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

/// Layout regression suite.
///
/// Flutter reports a layout overflow as a framework error — precisely the
/// "text overlapping / running off the edge" class of bug. Every widget below
/// is rendered at the narrowest phone width and at a raised text scale, and any
/// overflow fails the test.
///
/// Components rather than whole screens, deliberately: screens are these
/// widgets inside scrollables, and a scrollable cannot overflow along its
/// scroll axis. Every overflow this project has had came from a horizontal
/// `Row` or a fixed-height box — both of which live here. Full-screen tests
/// would also need a real database, whose async never settles under the test
/// binding's fake clock.
class Case {
  const Case(this.name, this.width, this.textScale);

  final String name;
  final double width;
  final double textScale;
}

const List<Case> cases = <Case>[
  Case('narrow-320', 320, 1.0),
  Case('phone-360', 360, 1.0),
  Case('narrow-320-large-text', 320, 1.3),
  Case('phone-360-huge-text', 360, 1.6),
];

const double _tallEnoughToIsolateHorizontalOverflow = 4000;

/// Renders [child] at [testCase]'s width and returns any layout errors.
Future<List<String>> render(
  WidgetTester tester,
  Widget child,
  Case testCase, {
  List<Override> overrides = const <Override>[],
}) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed') || message.contains('RenderFlex')) {
      errors.add(message.split('\n').first.trim());
    } else {
      previous?.call(details);
    }
  };

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        secureStoreProvider.overrideWithValue(InMemorySecureStore()),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(testCase.width, 800),
            textScaler: TextScaler.linear(testCase.textScale),
          ),
          child: Scaffold(
            body: SizedBox(
              width: testCase.width,
              // Unbounded height so a vertical overflow inside a card is not
              // mistaken for the screen simply being short.
              height: _tallEnoughToIsolateHorizontalOverflow,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    ),
  );

  // Fixed pumps rather than pumpAndSettle: the skeleton shimmer repeats
  // forever and would never settle.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }

  FlutterError.onError = previous;
  return errors;
}

void main() {
  setUpAll(() async {
    // A real font gives true glyph metrics. The default test font makes every
    // character the same width, which hides genuine overflow.
    //
    // Read synchronously: real file I/O awaited under the test binding's fake
    // clock never completes, and the suite hangs until it times out.
    const path =
        '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf';
    if (!File(path).existsSync()) return;
    final bytes = File(path).readAsBytesSync();
    final loader = FontLoader('Roboto')
      ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    await loader.load();
  });

  final now = DateTime.now();

  final lifeScoreOverride = lifeScoreProvider.overrideWith(
    (ref) async => LifeScore(
      computedAt: now,
      habits: 72,
      health: 61,
      finances: 80,
      productivity: 55,
      mood: 68,
      missingPillars: const <String>['Finances'],
    ),
  );

  // Long, realistic content — short strings never overflow and prove nothing.
  final fixtures = <String, Widget>{
    'ChipStrip (many chips)': ChipStrip(
      children: <Widget>[
        for (final label in <String>[
          'journal', 'photo', 'mood', 'milestone', 'expense', 'event', 'task',
        ])
          FilterChip(label: Text(label), onSelected: (_) {}, selected: false),
      ],
    ),
    'StatTile row (four across)': Row(
      children: <Widget>[
        for (final label in <String>['Sleep', 'Water', 'Move', 'Screen'])
          Expanded(
            child: StatTile(
              label: label,
              value: '10.5',
              unit: 'hours',
              delta: -0.42,
              progress: 0.6,
            ),
          ),
      ],
    ),
    'SectionHeader with trailing': const SectionHeader(
      title: 'A section title long enough to need the whole row',
      subtitle: 'And a subtitle underneath that is also rather long',
      onSeeAll: null,
    ),
    'GlassCard with long words': const GlassCard(
      child: Text('Antidisestablishmentarianism Donaudampfschifffahrts'),
    ),
    'ProgressRing with caption': const ProgressRing(
      value: 0.62,
      label: '62',
      caption: 'Running on empty',
    ),
    'BriefingCard': const BriefingCard(
      summary: 'Two deadlines today and one meeting you moved twice already. '
          'Your energy has been highest in the mornings this week.',
    ),
    'MoodCard': MoodCard(
      mood: MoodEntry(
        id: 'm',
        recordedAt: now,
        dayKey: '2026-07-27',
        happiness: 8,
        energy: 7,
      ),
    ),
    'HabitRingCard': HabitRingCard(
      completion: 0.5,
      habits: <HabitWithProgress>[
        for (var i = 0; i < 4; i++)
          HabitWithProgress(
            habit: Habit(
              id: 'h$i',
              name: 'Meditate for twenty minutes before opening any screen',
              createdAt: now,
            ),
            loggedAmount: i.isEven ? 1 : 0,
            streak: 12,
          ),
      ],
    ),
    'TasksCard': TasksCard(
      tasks: <Task>[
        for (var i = 0; i < 3; i++)
          Task(
            id: 't$i',
            title: 'Reply to the long email thread about quarterly planning',
            createdAt: now,
            dueAt: now.subtract(const Duration(hours: 3)),
            priority: TaskPriority.urgent,
            aiReason: 'Overdue and blocking two other people',
          ),
      ],
    ),
    'UpcomingCard': UpcomingCard(
      events: <CalendarEvent>[
        CalendarEvent(
          id: 'e',
          title: 'Quarterly planning review with the whole product team',
          start: now,
          end: now.add(const Duration(hours: 1)),
          createdAt: now,
          location: 'Meeting room four, second floor, north building',
        ),
      ],
    ),
    'MoneyCard': const MoneyCard(spentTodayMinor: 123456789),
    'HealthCard': const HealthCard(
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
    'LifeScoreCard': LifeScoreCard(
      journalStreak: 14,
      goals: <Goal>[
        Goal(
          id: 'g',
          title: 'Run a half marathon before the end of the year',
          createdAt: now,
          targetDate: now.add(const Duration(days: 60)),
        ),
      ],
    ),
  };

  for (final fixture in fixtures.entries) {
    for (final testCase in cases) {
      testWidgets('${fixture.key} @ ${testCase.name}', (tester) async {
        final errors = await render(
          tester,
          fixture.value,
          testCase,
          overrides: <Override>[lifeScoreOverride],
        );

        expect(
          errors,
          isEmpty,
          reason: '${fixture.key} at ${testCase.width}px '
              '× ${testCase.textScale}:\n${errors.join('\n')}',
        );
      });
    }
  }

  testWidgets('ChipStrip reserves height that grows with the text scale',
      (tester) async {
    late double normal;
    late double scaled;

    for (final scale in <double>[1.0, 1.5]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Builder(
              builder: (context) {
                if (scale == 1.0) {
                  normal = ChipStrip.heightFor(context);
                } else {
                  scaled = ChipStrip.heightFor(context);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    }

    expect(scaled, greaterThan(normal));
  });
}
