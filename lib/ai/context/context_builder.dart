import '../../core/utils/formatters.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/chat.dart';
import '../../domain/entities/finance.dart';
import '../../domain/entities/health_metric.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/mood_entry.dart';
import '../../domain/entities/task.dart';
import '../../domain/repositories/calendar_repository.dart';
import '../../domain/repositories/finance_repository.dart';
import '../../domain/repositories/goal_repository.dart';
import '../../domain/repositories/habit_repository.dart';
import '../../domain/repositories/health_repository.dart';
import '../../domain/repositories/journal_repository.dart';
import '../../domain/repositories/mood_repository.dart';
import '../../domain/repositories/search_repository.dart';
import '../../domain/repositories/task_repository.dart';
import 'life_context.dart';

/// Assembles the grounding set for an AI request.
///
/// Two strategies, deliberately different:
///  * [forRange] is *exhaustive within a window* — the right shape for reviews
///    and insights, where missing a week would change the conclusion.
///  * [forQuestion] is *retrieval* — it searches, then pulls only what matched,
///    because "when did I last see Alex?" does not need six months of expenses.
///
/// Both cap how much they emit. An oversized prompt is slower, costs more, and
/// measurably degrades answer quality, so the budget is a feature.
class ContextBuilder {
  const ContextBuilder({
    required this.journal,
    required this.mood,
    required this.habits,
    required this.goals,
    required this.tasks,
    required this.calendar,
    required this.finance,
    required this.health,
    required this.search,
  });

  final JournalRepository journal;
  final MoodRepository mood;
  final HabitRepository habits;
  final GoalRepository goals;
  final TaskRepository tasks;
  final CalendarRepository calendar;
  final FinanceRepository finance;
  final HealthRepository health;
  final SearchRepository search;

  static const int _defaultChunkBudget = 90;

  Future<LifeContext> forRange({
    required DateTime from,
    required DateTime to,
    int maxChunks = _defaultChunkBudget,
    String userName = '',
    List<String> focusAreas = const <String>[],
    String currency = 'USD',
  }) async {
    final chunks = <ContextChunk>[];
    final stats = <String, Object?>{};
    var counter = 0;
    String nextToken(String prefix) => '$prefix${++counter}';

    // --- Journal ---------------------------------------------------------
    final entries = await journal.page(limit: 40, offset: 0, from: from, to: to);
    for (final entry in entries.valueOrNull ?? const <JournalEntry>[]) {
      chunks.add(
        ContextChunk(
          token: nextToken('j'),
          source: CitationSource.journal,
          sourceId: entry.id,
          label: entry.displayTitle,
          occurredAt: entry.createdAt,
          // The AI summary when it exists, the raw text when it does not: both
          // are the user's own words, and the summary is cheaper.
          text: entry.analysis?.summary ??
              (entry.body.length > 600
                  ? '${entry.body.substring(0, 597)}…'
                  : entry.body),
        ),
      );
    }
    final streak = await journal.currentStreak();
    stats['journal streak (days)'] = streak.valueOrNull ?? 0;
    stats['journal entries in window'] =
        (entries.valueOrNull ?? const <JournalEntry>[]).length;

    // --- Mood ------------------------------------------------------------
    final moods = await mood.range(from, to);
    final moodList = moods.valueOrNull ?? const <MoodEntry>[];
    if (moodList.isNotEmpty) {
      for (final dimension in MoodDimension.values) {
        final average = moodList
                .map((m) => m.valueOf(dimension))
                .reduce((a, b) => a + b) /
            moodList.length;
        stats['avg ${dimension.label.toLowerCase()} (1-10)'] =
            average.toStringAsFixed(1);
      }
      for (final entry in moodList.take(14)) {
        chunks.add(
          ContextChunk(
            token: nextToken('m'),
            source: CitationSource.mood,
            sourceId: entry.id,
            label: '${entry.label} mood',
            occurredAt: entry.recordedAt,
            text: 'happiness ${entry.happiness}/10, energy ${entry.energy}/10, '
                'focus ${entry.focus}/10, stress ${entry.stress}/10'
                '${entry.note == null ? '' : ' — ${entry.note}'}',
          ),
        );
      }
      final correlations = await mood.correlations();
      for (final correlation
          in (correlations.valueOrNull ?? const <MoodCorrelation>[]).take(6)) {
        stats['pattern: ${correlation.factor}'] = correlation.description;
      }
    }

    // --- Habits ----------------------------------------------------------
    final habitList = await habits.watchHabits().first;
    for (final habit in habitList.take(15)) {
      final stat = await habits.stats(habit.id);
      final value = stat.valueOrNull;
      if (value == null) continue;
      chunks.add(
        ContextChunk(
          token: nextToken('h'),
          source: CitationSource.habit,
          sourceId: habit.id,
          label: habit.name,
          text: '${habit.name}: ${Fmt.percent(value.completionRate)} completion, '
              'current streak ${value.currentStreak}, best ${value.longestStreak}',
        ),
      );
    }

    // --- Goals -----------------------------------------------------------
    final goalList = await goals.watchGoals().first;
    for (final goal in goalList.take(12)) {
      chunks.add(
        ContextChunk(
          token: nextToken('g'),
          source: CitationSource.goal,
          sourceId: goal.id,
          label: goal.title,
          occurredAt: goal.targetDate,
          text: '${goal.title} — ${Fmt.percent(goal.progress)} done'
              '${goal.targetDate == null ? '' : ', due ${Fmt.shortDate(goal.targetDate!)}'}'
              '${goal.isAtRisk ? ' (behind schedule)' : ''}',
        ),
      );
    }

    // --- Tasks -----------------------------------------------------------
    final completed = await tasks.completedCount(from: from, to: to);
    stats['tasks completed in window'] = completed.valueOrNull ?? 0;
    final open = await tasks.all();
    final overdue =
        (open.valueOrNull ?? const <Task>[]).where((t) => t.isOverdue).toList();
    stats['tasks overdue'] = overdue.length;
    for (final task in overdue.take(8)) {
      chunks.add(
        ContextChunk(
          token: nextToken('t'),
          source: CitationSource.task,
          sourceId: task.id,
          label: task.title,
          occurredAt: task.dueAt,
          text: 'overdue task: ${task.title} (${task.priority.label} priority)',
        ),
      );
    }

    // --- Calendar --------------------------------------------------------
    final events = await calendar.range(from, to);
    stats['events in window'] =
        (events.valueOrNull ?? const <CalendarEvent>[]).length;
    for (final event in (events.valueOrNull ?? const <CalendarEvent>[]).take(15)) {
      chunks.add(
        ContextChunk(
          token: nextToken('e'),
          source: CitationSource.event,
          sourceId: event.id,
          label: event.title,
          occurredAt: event.start,
          text: '${event.title} (${event.kind.name})'
              '${event.location.isEmpty ? '' : ' at ${event.location}'}',
        ),
      );
    }

    // --- Money -----------------------------------------------------------
    final spend = await finance.spendByCategory(from, to);
    final byCategory = spend.valueOrNull ?? const <String, int>{};
    if (byCategory.isNotEmpty) {
      final total = byCategory.values.reduce((a, b) => a + b);
      stats['total spent in window'] = Fmt.money(total, currency: currency);
      final ranked = byCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in ranked.take(6)) {
        stats['spend: ${entry.key}'] =
            Fmt.money(entry.value, currency: currency);
      }
    }
    final subscriptions = await finance.detectSubscriptions();
    for (final subscription
        in (subscriptions.valueOrNull ?? const <DetectedSubscription>[]).take(6)) {
      chunks.add(
        ContextChunk(
          token: nextToken('x'),
          source: CitationSource.transaction,
          sourceId: subscription.transactionIds.last,
          label: subscription.merchant,
          occurredAt: subscription.lastChargedAt,
          text: 'recurring charge: ${subscription.merchant} '
              '${Fmt.money(subscription.amountMinor, currency: currency)} '
              'every ${subscription.intervalDays} days',
        ),
      );
    }

    // --- Health ----------------------------------------------------------
    for (final kind in <HealthKind>[
      HealthKind.sleep,
      HealthKind.exercise,
      HealthKind.steps,
      HealthKind.water,
      HealthKind.weight,
    ]) {
      final average = await health.average(kind, from: from, to: to);
      final value = average.valueOrNull;
      if (value != null) {
        stats['avg ${kind.label.toLowerCase()}'] =
            '${value.toStringAsFixed(1)} ${kind.unit}';
      }
    }

    return LifeContext(
      chunks: chunks.take(maxChunks).toList(),
      from: from,
      to: to,
      stats: stats,
      userName: userName,
      focusAreas: focusAreas,
    );
  }

  /// Retrieval path: search first, then hydrate only what matched.
  Future<LifeContext> forQuestion(
    String question, {
    int maxChunks = 30,
    String userName = '',
  }) async {
    final hits = await search.search(question, limit: maxChunks);
    final chunks = <ContextChunk>[];
    var counter = 0;

    for (final hit in hits.valueOrNull ?? const <SearchHit>[]) {
      chunks.add(
        ContextChunk(
          token: '${hit.source.name.substring(0, 1)}${++counter}',
          source: hit.source,
          sourceId: hit.id,
          label: hit.title,
          occurredAt: hit.occurredAt,
          text: hit.snippet,
        ),
      );
    }

    // A question about "this week" needs recent context even if no keyword
    // matched, so a short recency window is always appended.
    final now = DateTime.now();
    final recent = await forRange(
      from: now.subtract(const Duration(days: 14)),
      to: now,
      maxChunks: 25,
      userName: userName,
    );

    return LifeContext(
      chunks: <ContextChunk>[...chunks, ...recent.chunks],
      from: recent.from,
      to: recent.to,
      stats: recent.stats,
      userName: userName,
    );
  }
}
