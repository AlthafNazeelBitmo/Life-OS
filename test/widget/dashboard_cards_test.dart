import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/core/theme/app_theme.dart';
import 'package:lifeos/core/widgets/glass_card.dart';
import 'package:lifeos/core/widgets/progress_ring.dart';
import 'package:lifeos/core/widgets/stat_tile.dart';
import 'package:lifeos/core/widgets/state_views.dart';
import 'package:lifeos/core/error/failures.dart';

/// Wraps a widget in the minimum real app chrome: the theme extension the
/// glass surfaces read from, and a ProviderScope for anything that watches.
Widget host(Widget child, {Brightness brightness = Brightness.light}) {
  return ProviderScope(
    child: MaterialApp(
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('GlassCard', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(host(const GlassCard(child: Text('Hello'))));
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('is tappable when given a callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          GlassCard(
            onTap: () => taps++,
            child: const Text('Tap me'),
          ),
        ),
      );

      await tester.tap(find.byType(GlassCard));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('drops the blur layer in high contrast mode', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(highContrast: true),
            home: const Scaffold(body: GlassCard(child: Text('flat'))),
          ),
        ),
      );

      // Legibility must not depend on the effect, so high contrast renders an
      // opaque card with no BackdropFilter at all.
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('flat'), findsOneWidget);
    });

    testWidgets('exposes a semantic label when given one', (tester) async {
      await tester.pumpWidget(
        host(
          const GlassCard(
            semanticLabel: 'Today’s mood',
            child: Text('😄'),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(RegExp('Today')),
        findsAtLeastNWidgets(1),
      );
    });
  });

  group('StatTile', () {
    testWidgets('shows label, value and unit', (tester) async {
      await tester.pumpWidget(
        host(
          const StatTile(label: 'Sleep', value: '7.5', unit: 'h'),
        ),
      );

      expect(find.text('Sleep'), findsOneWidget);
      expect(find.text('7.5'), findsOneWidget);
      expect(find.text('h'), findsOneWidget);
    });

    testWidgets('pairs a delta with a direction arrow, not colour alone',
        (tester) async {
      await tester.pumpWidget(
        host(const StatTile(label: 'Steps', value: '9k', delta: 0.12)),
      );

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.text('12%'), findsOneWidget);
    });

    testWidgets('shows a downward arrow for a negative delta', (tester) async {
      await tester.pumpWidget(
        host(const StatTile(label: 'Spend', value: '£20', delta: -0.3)),
      );

      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    });
  });

  group('ProgressRing', () {
    testWidgets('renders the percentage by default', (tester) async {
      await tester.pumpWidget(host(const ProgressRing(value: 0.5)));
      await tester.pumpAndSettle();

      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('clamps out-of-range values', (tester) async {
      await tester.pumpWidget(host(const ProgressRing(value: 1.8)));
      await tester.pumpAndSettle();

      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('uses the explicit label when provided', (tester) async {
      await tester.pumpWidget(
        host(const ProgressRing(value: 0.7, label: '72', caption: 'Steady')),
      );
      await tester.pumpAndSettle();

      expect(find.text('72'), findsOneWidget);
      expect(find.text('Steady'), findsOneWidget);
    });
  });

  group('state views', () {
    testWidgets('EmptyState shows its message and action', (tester) async {
      await tester.pumpWidget(
        host(
          EmptyState(
            icon: Icons.menu_book_outlined,
            title: 'Nothing written yet',
            message: 'Start with one line.',
            action: FilledButton(onPressed: () {}, child: const Text('Write')),
          ),
        ),
      );

      expect(find.text('Nothing written yet'), findsOneWidget);
      expect(find.text('Write'), findsOneWidget);
    });

    testWidgets('ErrorView offers retry only for retryable failures',
        (tester) async {
      await tester.pumpWidget(
        host(ErrorView(failure: const NetworkFailure(), onRetry: () {})),
      );
      expect(find.text('Try again'), findsOneWidget);

      await tester.pumpWidget(
        host(
          ErrorView(
            failure: const ValidationFailure('Enter an amount'),
            onRetry: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Enter an amount'), findsOneWidget);
    });

    testWidgets('AsyncView keeps showing data while refreshing',
        (tester) async {
      const refreshing = AsyncLoading<String>();
      await tester.pumpWidget(
        host(
          AsyncView<String>(
            value: refreshing.copyWithPrevious(const AsyncData<String>('cached')),
            builder: (context, data) => Text(data),
          ),
        ),
      );

      // Stale data beats a spinner: the screen should not blank out on refresh.
      expect(find.text('cached'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  testWidgets('theme provides LifeOS tokens in both brightnesses',
      (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              final tokens = Theme.of(context).tokens;
              expect(tokens.heatRamp, isNotEmpty);
              expect(tokens.backdropGradient, hasLength(2));
              return const SizedBox.shrink();
            },
          ),
          brightness: brightness,
        ),
      );
    }
  });
}
