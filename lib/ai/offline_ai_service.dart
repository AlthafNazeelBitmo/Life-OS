import '../core/error/result.dart';
import '../core/extensions/date_time_x.dart';
import '../core/utils/formatters.dart';
import '../core/utils/ids.dart';
import '../domain/entities/finance.dart';
import '../domain/entities/goal.dart';
import '../domain/entities/habit.dart';
import '../domain/entities/insight.dart';
import '../domain/entities/mood_entry.dart';
import '../domain/entities/task.dart';
import 'ai_service.dart';
import 'context/life_context.dart';
import 'models/ai_results.dart';

/// [AIService] with no model behind it.
///
/// This is the default provider and the fallback for every other one. It is not
/// a stub: the statistics it reports are the same ones the model-backed service
/// is given, so the numbers a user sees are identical either way — only the
/// prose is plainer. That is the point. LifeOS has to be genuinely useful with
/// no AI account, no network, and nothing leaving the device.
class OfflineAiService implements AIService {
  const OfflineAiService();

  @override
  String get providerId => 'offline';

  @override
  String get model => 'on-device heuristics';

  @override
  bool get isRemote => false;

  // Small lexicons. Crude, but they run in microseconds and never mislabel a
  // whole entry the way an over-confident classifier can.
  static const Map<String, double> _sentimentLexicon = <String, double>{
    'happy': 0.8, 'joy': 0.9, 'great': 0.7, 'good': 0.5, 'love': 0.8,
    'excited': 0.8, 'proud': 0.7, 'calm': 0.5, 'grateful': 0.8, 'relaxed': 0.6,
    'productive': 0.6, 'win': 0.6, 'progress': 0.5, 'rest': 0.4, 'fun': 0.6,
    'tired': -0.4, 'exhausted': -0.7, 'sad': -0.8, 'angry': -0.8,
    'anxious': -0.7, 'stressed': -0.8, 'worried': -0.6, 'frustrated': -0.7,
    'lonely': -0.7, 'overwhelmed': -0.8, 'sick': -0.6, 'bad': -0.5,
    'failed': -0.7, 'stuck': -0.5, 'behind': -0.4,
  };

  static const Map<String, List<String>> _emotionLexicon =
      <String, List<String>>{
    'joy': <String>['happy', 'joy', 'delighted', 'great', 'fun', 'laughed'],
    'gratitude': <String>['grateful', 'thankful', 'appreciate'],
    'pride': <String>['proud', 'accomplished', 'achieved', 'finished'],
    'calm': <String>['calm', 'relaxed', 'peaceful', 'rested'],
    'anxiety': <String>['anxious', 'worried', 'nervous', 'panic'],
    'stress': <String>['stressed', 'overwhelmed', 'pressure', 'deadline'],
    'sadness': <String>['sad', 'down', 'low', 'lonely', 'miss'],
    'anger': <String>['angry', 'annoyed', 'frustrated', 'irritated'],
    'fatigue': <String>['tired', 'exhausted', 'drained', 'burnt out'],
  };

  static const Set<String> _stopWords = <String>{
    'the', 'and', 'was', 'were', 'that', 'this', 'with', 'have', 'had', 'for',
    'but', 'not', 'you', 'your', 'from', 'they', 'them', 'then', 'than', 'been',
    'about', 'just', 'like', 'what', 'when', 'will', 'would', 'could', 'their',
    'there', 'today', 'really', 'because', 'into', 'over', 'some', 'more',
  };

  @override
  Future<Result<AiSummary>> summarize(
    String text, {
    int maxSentences = 3,
    String? instruction,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const Ok<AiSummary>(AiSummary(summary: ''));
    }

    final sentences = _sentences(trimmed);
    // Extractive: score each sentence by how many of the document's frequent
    // words it contains, then keep the best few in their original order.
    final frequencies = _wordFrequencies(trimmed);
    final ranked = sentences.asMap().entries.map((entry) {
      final words = _words(entry.value);
      final score = words
          .map((word) => frequencies[word] ?? 0)
          .fold<int>(0, (sum, value) => sum + value);
      return (index: entry.key, sentence: entry.value, score: score / (words.length + 1));
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final picked = ranked.take(maxSentences).toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    final topics = (frequencies.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((entry) => entry.key)
        .toList();

    return Ok<AiSummary>(
      AiSummary(
        summary: picked.map((item) => item.sentence).join(' '),
        keyPoints: picked.map((item) => item.sentence).toList(),
        topics: topics,
        model: model,
      ),
    );
  }

  @override
  Future<Result<MoodAnalysis>> analyzeMood(
    String text, {
    MoodEntry? selfReported,
  }) async {
    final words = _words(text);
    if (words.isEmpty) {
      return const Ok<MoodAnalysis>(MoodAnalysis());
    }

    var total = 0.0;
    var hits = 0;
    for (final word in words) {
      final score = _sentimentLexicon[word];
      if (score != null) {
        total += score;
        hits++;
      }
    }
    // Fall back to the self-rating when the text carries no signal, rather than
    // reporting a confident neutral.
    final sentiment = hits > 0
        ? (total / hits).clamp(-1.0, 1.0)
        : (selfReported == null ? 0.0 : (selfReported.overall - 0.5) * 2);

    final emotions = <String>[];
    _emotionLexicon.forEach((emotion, markers) {
      if (markers.any((marker) => text.toLowerCase().contains(marker))) {
        emotions.add(emotion);
      }
    });

    final frequencies = _wordFrequencies(text);
    final themes = (frequencies.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(4)
        .map((entry) => entry.key)
        .toList();

    return Ok<MoodAnalysis>(
      MoodAnalysis(
        emotions: emotions,
        sentiment: sentiment,
        themes: themes,
        events: _sentences(text)
            .where((sentence) => RegExp(
                  r'\b(went|met|finished|started|bought|visited|called|saw)\b',
                  caseSensitive: false,
                ).hasMatch(sentence))
            .take(4)
            .toList(),
        people: _properNouns(text),
        note: hits == 0 ? 'No strong emotional language detected.' : '',
      ),
    );
  }

  @override
  Future<Result<List<Insight>>> generateInsights(LifeContext context) async {
    final insights = <Insight>[];
    final now = DateTime.now();

    // The correlation engine already did the statistics; these are surfaced
    // verbatim rather than re-derived.
    context.stats.forEach((key, value) {
      if (!key.startsWith('pattern: ')) return;
      insights.add(
        Insight(
          id: newId(),
          kind: InsightKind.correlation,
          title: key.substring(9),
          body: value.toString(),
          createdAt: now,
          confidence: 0.6,
          periodStart: context.from,
          periodEnd: context.to,
          model: model,
        ),
      );
    });

    final streak = context.stats['journal streak (days)'];
    if (streak is int && streak >= 3) {
      insights.add(
        Insight(
          id: newId(),
          kind: InsightKind.achievement,
          title: '$streak-day journalling streak',
          body: 'You have written every day for $streak days running.',
          createdAt: now,
          confidence: 1,
          periodStart: context.from,
          periodEnd: context.to,
          model: model,
        ),
      );
    }

    final overdue = context.stats['tasks overdue'];
    if (overdue is int && overdue > 3) {
      insights.add(
        Insight(
          id: newId(),
          kind: InsightKind.warning,
          title: '$overdue tasks are overdue',
          body: 'Consider rescheduling or dropping some — a backlog this size '
              'usually means the list, not the effort, needs changing.',
          createdAt: now,
          confidence: 0.9,
          periodStart: context.from,
          periodEnd: context.to,
          model: model,
        ),
      );
    }

    return Ok<List<Insight>>(insights.take(6).toList());
  }

  @override
  Future<Result<AiAnswer>> answerQuestion(
    String question,
    LifeContext context, {
    List<String> conversationHistory = const <String>[],
  }) async {
    // Without a model there is no summarising, so the honest answer is the
    // matching records themselves. Retrieval without generation still answers
    // "when did I last see Alex?" correctly.
    final terms = _words(question).where((w) => w.length > 3).toSet();
    final matches = context.chunks.where((chunk) {
      final haystack = '${chunk.label} ${chunk.text}'.toLowerCase();
      return terms.any(haystack.contains);
    }).toList()
      ..sort((a, b) => (b.occurredAt ?? DateTime(1970))
          .compareTo(a.occurredAt ?? DateTime(1970)));

    if (matches.isEmpty) {
      return Ok<AiAnswer>(
        AiAnswer(
          text: 'No AI provider is configured, so I can only search your own '
              'records — and nothing matched that question. Connect a provider '
              'in Settings › AI for written answers.',
          usedFallback: true,
          confidence: 0,
          model: model,
        ),
      );
    }

    final buffer = StringBuffer(
      'Here is what your records say (on-device search, no AI provider '
      'configured):\n\n',
    );
    for (final chunk in matches.take(6)) {
      final when =
          chunk.occurredAt == null ? '' : '${Fmt.shortDate(chunk.occurredAt!)} — ';
      buffer.writeln('• $when${chunk.text} [${chunk.token}]');
    }

    return Ok<AiAnswer>(
      AiAnswer(
        text: buffer.toString().trim(),
        citations: matches.take(6).map((c) => c.toCitation()).toList(),
        confidence: 1,
        usedFallback: true,
        model: model,
      ),
    );
  }

  @override
  Stream<String> answerQuestionStream(
    String question,
    LifeContext context, {
    List<String> conversationHistory = const <String>[],
  }) async* {
    final answer = await answerQuestion(
      question,
      context,
      conversationHistory: conversationHistory,
    );
    yield answer.valueOrNull?.text ?? 'Nothing to show.';
  }

  @override
  Future<Result<DayPlan>> planDay({
    required DateTime date,
    required List<Task> tasks,
    required LifeContext context,
  }) async {
    final ranked = tasks.where((task) => !task.isDone).toList()
      ..sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));

    // Greedy fill from 09:00, honouring each task's own estimate.
    final blocks = <PlannedBlock>[];
    var cursor = date.withTime(9, 0);
    final dayEnd = date.withTime(18, 0);

    for (final task in ranked) {
      final minutes = task.estimateMinutes ?? 45;
      final end = cursor.add(Duration(minutes: minutes));
      if (end.isAfter(dayEnd)) break;
      blocks.add(
        PlannedBlock(
          title: task.title,
          start: cursor,
          end: end,
          taskId: task.id,
          reason: task.isOverdue
              ? 'Overdue'
              : '${task.priority.label} priority',
          isFocusBlock: minutes >= 45,
        ),
      );
      // 10-minute gap between blocks; back-to-back plans never survive contact
      // with a real day.
      cursor = end.add(const Duration(minutes: 10));
    }

    final deferred = ranked
        .skip(blocks.length)
        .take(5)
        .map((task) => '${task.title} — no room today')
        .toList();

    return Ok<DayPlan>(
      DayPlan(
        date: date,
        blocks: blocks,
        topPriorities: ranked.take(3).map((task) => task.title).toList(),
        summary: blocks.isEmpty
            ? 'Nothing scheduled — add a task to get a plan.'
            : '${blocks.length} blocks, ordered by what is most urgent.',
        deferred: deferred,
        generatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<Result<ExpenseAnalysis>> analyzeExpenses({
    required DateTime from,
    required DateTime to,
    required LifeContext context,
    required int totalSpentMinor,
    required int totalIncomeMinor,
    required Map<String, int> byCategory,
    required List<DetectedSubscription> subscriptions,
    String currency = 'USD',
  }) async {
    final ranked = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final habits = <String>[
      if (ranked.isNotEmpty)
        'Your largest category was ${ranked.first.key} at '
            '${Fmt.money(ranked.first.value, currency: currency)}.',
      if (totalIncomeMinor > 0)
        'You kept ${Fmt.percent((totalIncomeMinor - totalSpentMinor) / totalIncomeMinor)} '
            'of what came in.',
    ];

    final suggestions = <String>[
      for (final subscription in subscriptions.take(3))
        'Cancelling ${subscription.merchant} would free '
            '${Fmt.money(subscription.annualCostMinor, currency: currency)} a year.',
      if (ranked.length > 1)
        'Trimming ${ranked.first.key} by 15% saves about '
            '${Fmt.money((ranked.first.value * 0.15).round(), currency: currency)} '
            'over this period.',
    ];

    final days = to.difference(from).inDays.clamp(1, 400);
    return Ok<ExpenseAnalysis>(
      ExpenseAnalysis(
        periodStart: from,
        periodEnd: to,
        totalSpentMinor: totalSpentMinor,
        totalIncomeMinor: totalIncomeMinor,
        currency: currency,
        byCategory: byCategory,
        habits: habits,
        savingsSuggestions: suggestions,
        subscriptions: subscriptions,
        // Straight-line run rate — no model needed, and honest about method.
        projectedNextMonthMinor: (totalSpentMinor / days * 30).round(),
        summary: 'You spent ${Fmt.money(totalSpentMinor, currency: currency)} '
            'over $days days across ${byCategory.length} categories.',
      ),
    );
  }

  @override
  Future<Result<List<HabitSuggestion>>> suggestHabits(
    LifeContext context,
  ) async {
    final suggestions = <HabitSuggestion>[];

    final sleep = context.stats['avg sleep'];
    if (sleep is String && (double.tryParse(sleep.split(' ').first) ?? 8) < 7) {
      suggestions.add(
        const HabitSuggestion(
          name: 'Lights out by 23:00',
          rationale: 'Your average sleep is under 7 hours.',
          emoji: '😴',
        ),
      );
    }

    final streak = context.stats['journal streak (days)'];
    if (streak is int && streak == 0) {
      suggestions.add(
        const HabitSuggestion(
          name: 'Write three lines a day',
          rationale: 'Nothing journalled recently — start small enough to keep.',
          emoji: '📓',
        ),
      );
    }

    final exercise = context.stats['avg exercise'];
    if (exercise == null) {
      suggestions.add(
        const HabitSuggestion(
          name: 'Walk 20 minutes',
          rationale: 'No exercise is being tracked yet, so there is nothing to '
              'correlate your mood against.',
          emoji: '🚶',
          target: 20,
          unit: 'min',
        ),
      );
    }

    return Ok<List<HabitSuggestion>>(suggestions);
  }

  @override
  Future<Result<PeriodReview>> weeklyReview(LifeContext context) =>
      periodReview(ReviewPeriod.weekly, context);

  @override
  Future<Result<PeriodReview>> monthlyReview(LifeContext context) =>
      periodReview(ReviewPeriod.monthly, context);

  @override
  Future<Result<PeriodReview>> periodReview(
    ReviewPeriod period,
    LifeContext context,
  ) async {
    final wins = <String>[];
    final attention = <String>[];

    final completed = context.stats['tasks completed in window'];
    if (completed is int && completed > 0) {
      wins.add('Completed $completed tasks.');
    }
    final streak = context.stats['journal streak (days)'];
    if (streak is int && streak > 0) {
      wins.add('Journalled $streak days in a row.');
    }
    final overdue = context.stats['tasks overdue'];
    if (overdue is int && overdue > 0) {
      attention.add('$overdue tasks are past their due date.');
    }
    final spent = context.stats['total spent in window'];
    if (spent != null) attention.add('Spending this period: $spent.');

    return Ok<PeriodReview>(
      PeriodReview(
        id: newId(),
        period: period,
        periodStart: context.from ?? DateTime.now().startOfWeek,
        periodEnd: context.to ?? DateTime.now(),
        generatedAt: DateTime.now(),
        headline: 'Your ${period.label.toLowerCase()}, from your own numbers',
        narrative: 'No AI provider is configured, so this review reports the '
            'figures LifeOS computed on-device. Connect a provider in '
            'Settings › AI for a written narrative.',
        wins: wins,
        attentionAreas: attention,
        metrics: <String, double>{
          for (final entry in context.stats.entries)
            if (entry.value is num) entry.key: (entry.value! as num).toDouble(),
        },
        model: model,
      ),
    );
  }

  @override
  Future<Result<GoalPlan>> planGoal(Goal goal, LifeContext context) async =>
      Ok<GoalPlan>(
        GoalPlan(
          goalId: goal.id,
          dailyTasks: <String>['Spend 20 minutes on "${goal.title}"'],
          weeklyPlan: <String>['Review progress on "${goal.title}"'],
          monthlyRoadmap: <String>[
            'Define what "done" looks like',
            'Complete the first third',
            'Complete the second third',
            'Finish and review',
          ],
          rationale: 'Generic breakdown — connect an AI provider for a plan '
              'shaped around your actual schedule.',
          generatedAt: DateTime.now(),
        ),
      );

  @override
  Future<Result<ParsedIntent>> parseIntent(String utterance) async {
    final text = utterance.toLowerCase().trim();

    // Regex parsing handles the common spoken forms well enough to be the
    // primary path when offline — "I spent $25 on lunch" is not ambiguous.
    final amount = RegExp(r'(\d+(?:[.,]\d{1,2})?)').firstMatch(text);
    final amountMinor = amount == null
        ? null
        : (double.parse(amount.group(1)!.replaceAll(',', '.')) * 100).round();

    if (RegExp(r'\b(spent|paid|bought|cost)\b').hasMatch(text) &&
        amountMinor != null) {
      final merchant = RegExp(r'\b(?:on|at|for)\s+([\w\s]+)').firstMatch(text);
      return Ok<ParsedIntent>(
        ParsedIntent(
          action: 'log_expense',
          fields: <String, Object?>{
            'amount_minor': amountMinor,
            'merchant': merchant?.group(1)?.trim() ?? '',
          },
          confidence: 0.8,
          transcript: utterance,
        ),
      );
    }

    if (RegExp(r'\b(earned|received|got paid|income)\b').hasMatch(text) &&
        amountMinor != null) {
      return Ok<ParsedIntent>(
        ParsedIntent(
          action: 'log_income',
          fields: <String, Object?>{'amount_minor': amountMinor},
          confidence: 0.75,
          transcript: utterance,
        ),
      );
    }

    if (RegExp(r'\b(went to the gym|worked out|exercised|ran|walked)\b')
        .hasMatch(text)) {
      return Ok<ParsedIntent>(
        ParsedIntent(
          action: 'log_health',
          fields: <String, Object?>{
            'kind': 'exercise',
            'value': amountMinor == null ? 30 : amountMinor / 100,
          },
          confidence: 0.7,
          transcript: utterance,
        ),
      );
    }

    if (RegExp(r'\b(drank|glass|water)\b').hasMatch(text)) {
      return Ok<ParsedIntent>(
        ParsedIntent(
          action: 'log_health',
          fields: <String, Object?>{'kind': 'water', 'value': 1},
          confidence: 0.7,
          transcript: utterance,
        ),
      );
    }

    if (RegExp(r'\b(remind me|todo|task|need to)\b').hasMatch(text)) {
      return Ok<ParsedIntent>(
        ParsedIntent(
          action: 'add_task',
          fields: <String, Object?>{
            'text': utterance,
            'when': _relativeDate(text)?.toIso8601String(),
          },
          confidence: 0.65,
          transcript: utterance,
        ),
      );
    }

    if (RegExp(r'\b(goal|want to|aim to)\b').hasMatch(text)) {
      return Ok<ParsedIntent>(
        ParsedIntent(
          action: 'create_goal',
          fields: <String, Object?>{'text': utterance},
          confidence: 0.6,
          transcript: utterance,
        ),
      );
    }

    // Anything unrecognised becomes a journal entry rather than being lost.
    return Ok<ParsedIntent>(
      ParsedIntent(
        action: 'journal',
        fields: <String, Object?>{'text': utterance},
        confidence: 0.4,
        transcript: utterance,
      ),
    );
  }

  @override
  Future<Result<String>> dailyBriefing(LifeContext context) async {
    final parts = <String>[];
    final events = context.stats['events in window'];
    if (events is int && events > 0) parts.add('$events events in your window.');
    final overdue = context.stats['tasks overdue'];
    if (overdue is int && overdue > 0) parts.add('$overdue tasks are overdue.');
    final streak = context.stats['journal streak (days)'];
    if (streak is int && streak > 0) {
      parts.add('Journal streak: $streak days.');
    }
    return Ok<String>(
      parts.isEmpty
          ? 'Nothing scheduled and nothing overdue. A clear day.'
          : parts.join(' '),
    );
  }

  @override
  Future<Result<List<String>>> reflectionQuestions(LifeContext context) async =>
      const Ok<List<String>>(<String>[
        'What went better today than you expected?',
        'What took more out of you than it should have?',
        'What is the one thing worth carrying into tomorrow?',
      ]);

  // --- text helpers -------------------------------------------------------

  static List<String> _sentences(String text) => text
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.length > 2)
      .toList();

  static List<String> _words(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2)
      .toList();

  static Map<String, int> _wordFrequencies(String text) {
    final frequencies = <String, int>{};
    for (final word in _words(text)) {
      if (_stopWords.contains(word)) continue;
      frequencies[word] = (frequencies[word] ?? 0) + 1;
    }
    return frequencies;
  }

  /// Capitalised words that are not sentence-initial — a decent proxy for
  /// names when there is no model to ask.
  static List<String> _properNouns(String text) {
    final names = <String>{};
    for (final sentence in _sentences(text)) {
      final tokens = sentence.split(RegExp(r'\s+'));
      for (var i = 1; i < tokens.length; i++) {
        final token = tokens[i].replaceAll(RegExp(r'[^A-Za-z]'), '');
        if (token.length > 2 &&
            token[0] == token[0].toUpperCase() &&
            token.substring(1) == token.substring(1).toLowerCase()) {
          names.add(token);
        }
      }
    }
    return names.take(6).toList();
  }

  static DateTime? _relativeDate(String text) {
    final now = DateTime.now();
    if (text.contains('tomorrow')) return now.addDays(1).withTime(9, 0);
    if (text.contains('tonight')) return now.withTime(20, 0);
    if (text.contains('next week')) return now.addDays(7).withTime(9, 0);
    if (text.contains('today')) return now.withTime(18, 0);
    return null;
  }
}
