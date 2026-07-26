import '../core/error/result.dart';
import '../domain/entities/finance.dart';
import '../domain/entities/goal.dart';
import '../domain/entities/habit.dart';
import '../domain/entities/insight.dart';
import '../domain/entities/mood_entry.dart';
import '../domain/entities/task.dart';
import 'context/life_context.dart';
import 'models/ai_results.dart';

/// The app's entire AI surface.
///
/// Feature code depends on this and nothing else — never on a provider, a
/// model name, or an HTTP client. Two implementations ship: `DefaultAiService`
/// (any [LlmClient]) and `OfflineAiService` (on-device heuristics), and they are
/// interchangeable, which is what lets LifeOS be fully useful with no AI
/// account at all.
///
/// Contract for every method:
///  * grounded — answers may only assert what is in the supplied [LifeContext];
///  * cited — claims carry [Citation]s resolved back to real records;
///  * total — failures come back as `Err`, never as a thrown exception.
abstract interface class AIService {
  /// Identifier of the backing provider, for provenance badges.
  String get providerId;

  String get model;

  /// True when this implementation needs the network.
  bool get isRemote;

  /// Condenses text — a journal entry, a week of notes, a transcript.
  Future<Result<AiSummary>> summarize(
    String text, {
    int maxSentences = 3,
    String? instruction,
  });

  /// Extracts emotions, themes, events and people from free text.
  Future<Result<MoodAnalysis>> analyzeMood(
    String text, {
    MoodEntry? selfReported,
  });

  /// Finds patterns worth surfacing. The statistical work happens on-device
  /// first; the model's job is to explain what was already found, not to
  /// discover it by eyeballing numbers.
  Future<Result<List<Insight>>> generateInsights(LifeContext context);

  /// Free-form question answering over the user's own history.
  Future<Result<AiAnswer>> answerQuestion(
    String question,
    LifeContext context, {
    List<String> conversationHistory = const <String>[],
  });

  /// Streaming variant used by the chat screen. Emits partial text; the final
  /// grounded answer arrives through [answerQuestion] semantics on completion.
  Stream<String> answerQuestionStream(
    String question,
    LifeContext context, {
    List<String> conversationHistory = const <String>[],
  });

  /// Builds a realistic plan for [date] around existing commitments.
  Future<Result<DayPlan>> planDay({
    required DateTime date,
    required List<Task> tasks,
    required LifeContext context,
  });

  Future<Result<ExpenseAnalysis>> analyzeExpenses({
    required DateTime from,
    required DateTime to,
    required LifeContext context,
    required int totalSpentMinor,
    required int totalIncomeMinor,
    required Map<String, int> byCategory,
    required List<DetectedSubscription> subscriptions,
    String currency = 'USD',
  });

  /// Proposes habits grounded in what the user has actually written and aimed
  /// at. Suggestions carry the record ids that motivated them.
  Future<Result<List<HabitSuggestion>>> suggestHabits(LifeContext context);

  Future<Result<PeriodReview>> weeklyReview(LifeContext context);

  Future<Result<PeriodReview>> monthlyReview(LifeContext context);

  /// Quarterly and yearly reviews reuse the monthly pipeline with a wider
  /// window; exposed separately so callers can be explicit.
  Future<Result<PeriodReview>> periodReview(
    ReviewPeriod period,
    LifeContext context,
  );

  /// Breaks a goal into daily tasks, a weekly plan and a monthly roadmap.
  Future<Result<GoalPlan>> planGoal(Goal goal, LifeContext context);

  /// Turns a spoken sentence into a structured action.
  Future<Result<ParsedIntent>> parseIntent(String utterance);

  /// The morning briefing and evening reflection.
  Future<Result<String>> dailyBriefing(LifeContext context);

  Future<Result<List<String>>> reflectionQuestions(LifeContext context);
}
