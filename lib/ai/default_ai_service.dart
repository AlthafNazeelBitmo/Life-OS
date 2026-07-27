import 'dart:async';

import '../core/error/failures.dart';
import '../core/error/result.dart';
import '../core/extensions/date_time_x.dart';
import '../core/utils/app_logger.dart';
import '../core/utils/ids.dart';
import '../domain/entities/chat.dart';
import '../domain/entities/finance.dart';
import '../domain/entities/goal.dart';
import '../domain/entities/habit.dart';
import '../domain/entities/insight.dart';
import '../domain/entities/mood_entry.dart';
import '../domain/entities/task.dart';
import 'ai_service.dart';
import 'context/life_context.dart';
import 'json_extractor.dart';
import 'llm_client.dart';
import 'models/ai_results.dart';
import 'models/llm.dart';
import 'prompts/prompt_library.dart';

/// [AIService] on top of any [LlmClient].
///
/// This class owns everything that is *not* provider-specific: prompt
/// assembly, grounding, citation resolution, lenient parsing, retries, and the
/// fallback to on-device behaviour when a call fails. That is why adding a
/// fifth provider is a one-file change.
class DefaultAiService implements AIService {
  DefaultAiService(this._client, {AIService? fallback}) : _fallback = fallback;

  final LlmClient _client;

  /// Used when the model call fails outright. A degraded answer the user can
  /// act on beats an error dialog.
  final AIService? _fallback;

  static const int _maxAttempts = 2;

  @override
  String get providerId => _client.providerId;

  @override
  String get model => _client.model;

  @override
  bool get isRemote => providerId != 'ollama';

  /// One model call with a single retry on transient failures.
  ///
  /// Retrying more than once is not worth it: by the third attempt the user has
  /// been waiting long enough that the offline path is the better answer.
  Future<LlmCompletion> _call(
    String prompt, {
    required LlmResponseFormat format,
    String system = '',
    List<String> history = const <String>[],
    double temperature = 0.4,
    int maxTokens = 1200,
  }) async {
    final request = LlmRequest(
      messages: <LlmMessage>[
        LlmMessage.system(system.isEmpty ? Prompts.system() : system),
        for (final turn in history) LlmMessage.user(turn),
        LlmMessage.user(prompt),
      ],
      format: format,
      temperature: temperature,
      maxTokens: maxTokens,
    );

    AiFailure? lastFailure;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        return await _client.complete(request);
      } on AiFailure catch (failure) {
        lastFailure = failure;
        if (!failure.retryable) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      } on TimeoutException catch (error) {
        lastFailure = AiFailure(
          'The AI service took too long to respond.',
          provider: providerId,
          cause: error,
        );
      }
    }
    throw lastFailure ??
        AiFailure('The AI request failed.', provider: providerId);
  }

  /// Runs [body], falling back to the on-device service when the model path
  /// fails for any reason.
  Future<Result<T>> _guarded<T>(
    Future<T> Function() body,
    Future<Result<T>> Function(AIService fallback)? viaFallback,
  ) async {
    try {
      return Ok<T>(await body());
    } catch (error) {
      AppLogger.warn('ai', 'Call failed on $providerId', error);
      final fallback = _fallback;
      if (fallback != null && viaFallback != null) {
        return viaFallback(fallback);
      }
      if (error is Failure) return Err<T>(error);
      return Err<T>(
        AiFailure(
          'The assistant could not complete that request.',
          provider: providerId,
          cause: error,
        ),
      );
    }
  }

  Map<String, dynamic> _requireJson(LlmCompletion completion) {
    final json = JsonExtractor.object(completion.text);
    if (json == null) {
      throw AiFailure(
        'The AI returned an unreadable response.',
        provider: providerId,
        retryable: true,
      );
    }
    return json;
  }

  @override
  Future<Result<AiSummary>> summarize(
    String text, {
    int maxSentences = 3,
    String? instruction,
  }) =>
      _guarded(
        () async {
          final completion = await _call(
            Prompts.summarize(
              text,
              maxSentences: maxSentences,
              instruction: instruction,
            ),
            format: LlmResponseFormat.json,
            temperature: 0.3,
            maxTokens: 500,
          );
          return AiSummary.fromJson(_requireJson(completion))
              .withCitations(const <Citation>[], completion.model);
        },
        (fallback) => fallback.summarize(
          text,
          maxSentences: maxSentences,
          instruction: instruction,
        ),
      );

  @override
  Future<Result<MoodAnalysis>> analyzeMood(
    String text, {
    MoodEntry? selfReported,
  }) =>
      _guarded(
        () async {
          final completion = await _call(
            Prompts.analyzeMood(
              text,
              selfReported: selfReported == null
                  ? null
                  : '${selfReported.label} '
                      '(happiness ${selfReported.happiness}/10, '
                      'energy ${selfReported.energy}/10)',
            ),
            format: LlmResponseFormat.json,
            temperature: 0.2,
            maxTokens: 600,
          );
          return MoodAnalysis.fromJson(_requireJson(completion));
        },
        (fallback) => fallback.analyzeMood(text, selfReported: selfReported),
      );

  @override
  Future<Result<List<Insight>>> generateInsights(LifeContext context) =>
      _guarded(
        () async {
          if (context.isEmpty) return const <Insight>[];
          final completion = await _call(
            Prompts.insights(context),
            system: Prompts.system(userName: context.userName),
            format: LlmResponseFormat.json,
            temperature: 0.5,
            maxTokens: 1600,
          );

          final json = _requireJson(completion);
          final raw = json['insights'] as List<dynamic>? ?? const <dynamic>[];

          return raw.whereType<Map<String, dynamic>>().map((item) {
            final body = item['body'] as String? ?? '';
            // Trust the tokens the model actually used in its prose over the
            // ones it listed, then keep only those that resolve.
            final tokens = <String>{
              ...JsonExtractor.citationTokens(body),
              ...(item['citations'] as List<dynamic>? ?? const <dynamic>[])
                  .map((t) => t.toString()),
            };
            final citations = context.resolve(tokens);

            return Insight(
              id: newId(),
              kind: _insightKind(item['kind'] as String?),
              title: item['title'] as String? ?? 'Insight',
              body: body,
              createdAt: DateTime.now(),
              citations: citations,
              confidence: _confidence(item['confidence'], citations.isNotEmpty),
              periodStart: context.from,
              periodEnd: context.to,
              model: completion.model,
            );
          }).toList();
        },
        (fallback) => fallback.generateInsights(context),
      );

  @override
  Future<Result<AiAnswer>> answerQuestion(
    String question,
    LifeContext context, {
    List<String> conversationHistory = const <String>[],
  }) =>
      _guarded(
        () async {
          final completion = await _call(
            Prompts.answer(question, context, history: conversationHistory),
            system: Prompts.system(userName: context.userName),
            format: LlmResponseFormat.text,
            temperature: 0.4,
            maxTokens: 900,
          );

          final tokens = JsonExtractor.citationTokens(completion.text);
          final citations = context.resolve(tokens);

          // If the model cited tokens that do not exist, it was working from
          // something other than the user's data. Say so rather than presenting
          // it as fact.
          final unresolved = tokens.length - citations.length;
          final confidence = tokens.isEmpty
              ? 0.6
              : (1 - unresolved / tokens.length).clamp(0.0, 1.0);

          return AiAnswer(
            text: completion.text.trim(),
            citations: citations,
            confidence: confidence,
            model: completion.model,
          );
        },
        (fallback) => fallback.answerQuestion(
          question,
          context,
          conversationHistory: conversationHistory,
        ),
      );

  @override
  Stream<String> answerQuestionStream(
    String question,
    LifeContext context, {
    List<String> conversationHistory = const <String>[],
  }) async* {
    final request = LlmRequest(
      messages: <LlmMessage>[
        LlmMessage.system(Prompts.system(userName: context.userName)),
        for (final turn in conversationHistory) LlmMessage.user(turn),
        LlmMessage.user(
          Prompts.answer(question, context, history: conversationHistory),
        ),
      ],
      maxTokens: 900,
    );

    try {
      yield* _client.stream(request);
    } on AiFailure catch (failure) {
      // Streaming failures are surfaced as text rather than thrown: the chat
      // bubble is already on screen and an exception would blank it.
      yield '\n\n_${failure.message}_';
    }
  }

  @override
  Future<Result<DayPlan>> planDay({
    required DateTime date,
    required List<Task> tasks,
    required LifeContext context,
  }) =>
      _guarded(
        () async {
          final taskList = tasks
              .map(
                (task) => '- ${task.id} | ${task.title} | '
                    '${task.priority.label}'
                    '${task.dueAt == null ? '' : ' | due ${task.dueAt!.toIso8601String()}'}'
                    '${task.estimateMinutes == null ? '' : ' | ~${task.estimateMinutes}min'}',
              )
              .join('\n');

          final completion = await _call(
            Prompts.planDay(date, taskList, context),
            system: Prompts.system(userName: context.userName),
            format: LlmResponseFormat.json,
            temperature: 0.4,
            maxTokens: 1400,
          );

          final json = _requireJson(completion);
          final blocks = (json['blocks'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map((item) {
                final start = _timeOn(date, item['start'] as String?);
                final end = _timeOn(date, item['end'] as String?);
                if (start == null || end == null || !end.isAfter(start)) {
                  return null;
                }
                return PlannedBlock(
                  title: item['title'] as String? ?? 'Focus',
                  start: start,
                  end: end,
                  taskId: item['task_id'] as String?,
                  reason: item['reason'] as String? ?? '',
                  isFocusBlock: item['is_focus_block'] as bool? ?? false,
                );
              })
              .whereType<PlannedBlock>()
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));

          return DayPlan(
            date: date,
            blocks: blocks,
            topPriorities: _strings(json['top_priorities']),
            summary: json['summary'] as String?,
            deferred: _strings(json['deferred']),
            generatedAt: DateTime.now(),
          );
        },
        (fallback) =>
            fallback.planDay(date: date, tasks: tasks, context: context),
      );

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
  }) =>
      _guarded(
        () async {
          final completion = await _call(
            Prompts.expenses(context, currency),
            system: Prompts.system(userName: context.userName),
            format: LlmResponseFormat.json,
            temperature: 0.35,
            maxTokens: 1000,
          );
          final json = _requireJson(completion);

          return ExpenseAnalysis(
            periodStart: from,
            periodEnd: to,
            // Figures come from the database, never from the model — it is
            // asked to interpret them, not to add them up.
            totalSpentMinor: totalSpentMinor,
            totalIncomeMinor: totalIncomeMinor,
            currency: currency,
            byCategory: byCategory,
            habits: _strings(json['habits']),
            savingsSuggestions: _strings(json['savings_suggestions']),
            subscriptions: subscriptions,
            projectedNextMonthMinor:
                (json['projected_next_month_minor'] as num?)?.round(),
            summary: json['summary'] as String?,
          );
        },
        (fallback) => fallback.analyzeExpenses(
          from: from,
          to: to,
          context: context,
          totalSpentMinor: totalSpentMinor,
          totalIncomeMinor: totalIncomeMinor,
          byCategory: byCategory,
          subscriptions: subscriptions,
          currency: currency,
        ),
      );

  @override
  Future<Result<List<HabitSuggestion>>> suggestHabits(LifeContext context) =>
      _guarded(
        () async {
          final completion = await _call(
            Prompts.habitSuggestions(context),
            system: Prompts.system(userName: context.userName),
            format: LlmResponseFormat.json,
            temperature: 0.6,
            maxTokens: 900,
          );
          final json = _requireJson(completion);

          return (json['suggestions'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(
                (item) => HabitSuggestion(
                  name: item['name'] as String? ?? 'New habit',
                  rationale: item['rationale'] as String? ?? '',
                  emoji: item['emoji'] as String? ?? '✨',
                  cadence: switch (item['cadence']) {
                    'weekly' => HabitCadence.weekly,
                    'monthly' => HabitCadence.monthly,
                    _ => HabitCadence.daily,
                  },
                  target: (item['target'] as num?)?.round() ?? 1,
                  unit: item['unit'] as String? ?? '',
                  basedOn: context
                      .resolve(_strings(item['based_on']))
                      .map((citation) => citation.id)
                      .toList(),
                ),
              )
              .toList();
        },
        (fallback) => fallback.suggestHabits(context),
      );

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
  ) =>
      _guarded(
        () async {
          final completion = await _call(
            Prompts.review(period, context),
            system: Prompts.system(userName: context.userName),
            format: LlmResponseFormat.json,
            temperature: 0.5,
            maxTokens: 1800,
          );
          final json = _requireJson(completion);

          final narrative = json['narrative'] as String? ?? '';
          final tokens = <String>{
            ...JsonExtractor.citationTokens(narrative),
            ..._strings(json['citations']),
          };

          return PeriodReview(
            id: newId(),
            period: period,
            periodStart: context.from ?? DateTime.now().startOfWeek,
            periodEnd: context.to ?? DateTime.now(),
            generatedAt: DateTime.now(),
            headline: json['headline'] as String? ?? '',
            narrative: narrative,
            wins: _strings(json['wins']),
            attentionAreas: _strings(json['attention_areas']),
            recommendations: _strings(json['recommendations']),
            metrics: _metrics(context),
            citations: context.resolve(tokens),
            model: completion.model,
          );
        },
        (fallback) => fallback.periodReview(period, context),
      );

  @override
  Future<Result<GoalPlan>> planGoal(Goal goal, LifeContext context) => _guarded(
        () async {
          final completion = await _call(
            Prompts.goalPlan(goal.title, goal.description, context),
            system: Prompts.system(userName: context.userName),
            format: LlmResponseFormat.json,
            temperature: 0.5,
            maxTokens: 1200,
          );
          final json = _requireJson(completion);

          return GoalPlan(
            goalId: goal.id,
            dailyTasks: _strings(json['daily_tasks']),
            weeklyPlan: _strings(json['weekly_plan']),
            monthlyRoadmap: _strings(json['monthly_roadmap']),
            suggestedHabits: _strings(json['suggested_habits']),
            rationale: json['rationale'] as String?,
            generatedAt: DateTime.now(),
          );
        },
        (fallback) => fallback.planGoal(goal, context),
      );

  @override
  Future<Result<ParsedIntent>> parseIntent(String utterance) => _guarded(
        () async {
          final completion = await _call(
            Prompts.parseIntent(
              utterance,
              DateTime.now().toIso8601String().substring(0, 10),
            ),
            format: LlmResponseFormat.json,
            temperature: 0.1,
            maxTokens: 400,
          );
          return ParsedIntent.fromJson(_requireJson(completion))
              .withTranscript(utterance);
        },
        (fallback) => fallback.parseIntent(utterance),
      );

  @override
  Future<Result<String>> dailyBriefing(LifeContext context) => _guarded(
        () async {
          final completion = await _call(
            Prompts.dailyBriefing(context),
            system: Prompts.system(userName: context.userName),
            format: LlmResponseFormat.text,
            temperature: 0.5,
            maxTokens: 400,
          );
          return completion.text.trim();
        },
        (fallback) => fallback.dailyBriefing(context),
      );

  @override
  Future<Result<List<String>>> reflectionQuestions(LifeContext context) =>
      _guarded(
        () async {
          final completion = await _call(
            Prompts.reflectionQuestions(context),
            system: Prompts.system(userName: context.userName),
            format: LlmResponseFormat.json,
            temperature: 0.7,
            maxTokens: 400,
          );
          return _strings(_requireJson(completion)['questions']);
        },
        (fallback) => fallback.reflectionQuestions(context),
      );

  // --- helpers -----------------------------------------------------------

  static List<String> _strings(Object? value) => switch (value) {
        final List<dynamic> list => list
            .map((item) => item.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        _ => const <String>[],
      };

  static InsightKind _insightKind(String? raw) => switch (raw) {
        'correlation' => InsightKind.correlation,
        'achievement' => InsightKind.achievement,
        'warning' => InsightKind.warning,
        'recommendation' => InsightKind.recommendation,
        'milestone' => InsightKind.milestone,
        _ => InsightKind.pattern,
      };

  /// An uncited claim is capped below the "shown as fact" threshold no matter
  /// how confident the model says it is.
  static double _confidence(Object? raw, bool hasCitations) {
    final stated = switch (raw) {
      final num value => value.toDouble(),
      final String value => double.tryParse(value) ?? 0.6,
      _ => 0.6,
    }
        .clamp(0.0, 1.0);
    return hasCitations ? stated : stated.clamp(0.0, 0.45);
  }

  static Map<String, double> _metrics(LifeContext context) {
    final metrics = <String, double>{};
    context.stats.forEach((key, value) {
      final numeric = switch (value) {
        final num v => v.toDouble(),
        final String v => double.tryParse(v),
        _ => null,
      };
      if (numeric != null) metrics[key] = numeric;
    });
    return metrics;
  }

  static DateTime? _timeOn(DateTime date, String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}
