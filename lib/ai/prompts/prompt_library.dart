import '../../domain/entities/insight.dart';
import '../context/life_context.dart';

/// Every prompt in LifeOS, in one place.
///
/// Two things are non-negotiable in all of them and are stated in the shared
/// preamble rather than repeated per task:
///  1. only the supplied records may be asserted;
///  2. every claim carries a `[token]` citation.
///
/// The JSON-shaped tasks specify their schema inline and ask for JSON only.
/// Parsing stays lenient anyway — see `JsonExtractor`.
abstract final class Prompts {
  const Prompts._();

  /// Shared behavioural contract.
  static String system({String userName = ''}) => '''
You are the assistant inside LifeOS, a personal operating system app. You are
the user's chief of staff: observant, concise, and useful. ${userName.isEmpty ? '' : 'The user is $userName.'}

Rules you must follow:
- Ground every statement in the RECORDS and AGGREGATES you are given. If the
  data does not support an answer, say plainly what is missing. Never invent a
  number, a date, an event or a person.
- Cite the records you used with their bracket tokens, e.g. [j3] or [h1]. Put
  the citation immediately after the claim it supports.
- Prefer specifics from the data over general advice. "You journalled 5 of the
  last 7 days [j2][j4]" beats "journalling is a good habit".
- When a pattern is weak or the sample is small, say so instead of overstating.
- Never moralise about the user's choices, health, money or mood. Describe what
  the data shows and, when asked, what might help.
- Be brief. The user is reading this on a phone.
''';

  static String _dataBlock(LifeContext context) => '''
--- BEGIN DATA ---
${context.render()}
--- END DATA ---
''';

  static String summarize(
    String text, {
    int maxSentences = 3,
    String? instruction,
  }) =>
      '''
Summarise the following text in at most $maxSentences sentences.
${instruction ?? ''}

Return JSON only:
{"summary": "...", "key_points": ["..."], "topics": ["..."]}

TEXT:
$text
''';

  static String analyzeMood(String text, {String? selfReported}) => '''
Analyse this journal entry. Identify the emotions actually expressed (not
prescribed), the recurring themes, concrete events that happened, and people
mentioned by name.
${selfReported == null ? '' : 'The user separately rated their day as: $selfReported. If the text disagrees with the rating, trust the text and note the gap.'}

Return JSON only:
{"emotions": ["..."], "sentiment": -1.0..1.0, "themes": ["..."],
 "events": ["..."], "people": ["..."], "note": "one short observation"}

ENTRY:
$text
''';

  static String insights(LifeContext context) => '''
${_dataBlock(context)}

The AGGREGATES section already contains patterns computed from the user's data
statistically. Your job is to select the ones that matter and explain them in
plain language — not to derive new correlations by inspecting records.

Produce between 3 and 6 insights. Skip anything trivial or obvious.

Return JSON only:
{"insights": [
  {"kind": "pattern|correlation|achievement|warning|recommendation",
   "title": "short, specific",
   "body": "2-3 sentences, with [token] citations",
   "confidence": 0.0..1.0,
   "citations": ["j1", "h2"]}
]}
''';

  static String answer(
    String question,
    LifeContext context, {
    List<String> history = const <String>[],
  }) =>
      '''
${_dataBlock(context)}
${history.isEmpty ? '' : 'Earlier in this conversation:\n${history.join('\n')}\n'}
Answer the user's question using only the data above. Cite tokens inline.
If the data cannot answer it, say what you would need them to track.

QUESTION: $question
''';

  static String planDay(
    DateTime date,
    String taskList,
    LifeContext context,
  ) =>
      '''
${_dataBlock(context)}

Plan ${date.toIso8601String().substring(0, 10)} for the user. Work around the
existing calendar events in the data — do not schedule over them. Respect
energy patterns visible in the AGGREGATES if any are present.

Be realistic: a plan the user cannot finish is worse than a short one. Put
anything that will not fit into "deferred" and say so.

TASKS AVAILABLE:
$taskList

Return JSON only:
{"summary": "one sentence",
 "top_priorities": ["..."],
 "blocks": [{"title": "...", "start": "HH:mm", "end": "HH:mm",
             "task_id": "id or null", "reason": "why now",
             "is_focus_block": true|false}],
 "deferred": ["what is not happening today and why"]}
''';

  static String expenses(LifeContext context, String currency) => '''
${_dataBlock(context)}

Analyse this spending. The totals in AGGREGATES are authoritative — do not
recompute them. Amounts are in $currency.

Comment on habits visible in the data, name concrete savings opportunities with
figures, and flag any recurring charges that look forgotten. Do not lecture.

Return JSON only:
{"summary": "2-3 sentences with [token] citations",
 "habits": ["..."],
 "savings_suggestions": ["specific, with amounts"],
 "projected_next_month_minor": integer or null}
''';

  static String habitSuggestions(LifeContext context) => '''
${_dataBlock(context)}

Suggest 2 to 4 habits that follow from what this person has actually written,
their stated goals, and their sleep/mood/energy data. Each suggestion must name
the records that motivated it.

Do not suggest something they already track. Keep targets small enough to be
kept on a bad week.

Return JSON only:
{"suggestions": [
  {"name": "...", "emoji": "...", "cadence": "daily|weekly|monthly",
   "target": 1, "unit": "", "rationale": "with [token] citations",
   "based_on": ["j1", "g2"]}
]}
''';

  static String review(ReviewPeriod period, LifeContext context) => '''
${_dataBlock(context)}

Write the user's ${period.label.toLowerCase()}.

Be a chief of staff, not a cheerleader: name what went well, what slipped, and
what you would change. Use their real numbers with [token] citations. If a
pillar has no data, say it is untracked rather than guessing.

Return JSON only:
{"headline": "one memorable line about this period",
 "narrative": "3-5 sentences",
 "wins": ["..."],
 "attention_areas": ["..."],
 "recommendations": ["concrete, doable next period"],
 "citations": ["j1", "h3"]}
''';

  static String goalPlan(String title, String description, LifeContext context) =>
      '''
${_dataBlock(context)}

Break this goal into an actionable plan that fits the life visible in the data
above — their existing commitments, habits and energy.

GOAL: $title
DETAIL: $description

Return JSON only:
{"daily_tasks": ["small, repeatable"],
 "weekly_plan": ["..."],
 "monthly_roadmap": ["milestone-sized steps in order"],
 "suggested_habits": ["..."],
 "rationale": "why this sequence"}
''';

  static String parseIntent(String utterance, String today) => '''
Convert this spoken sentence into a single structured action. Today is $today.

Actions and their fields:
- log_expense: {"amount": number, "merchant": string, "category": string}
- log_income:  {"amount": number, "source": string}
- log_habit:   {"habit": string}
- log_mood:    {"happiness": 1-10, "energy": 1-10, "note": string}
- log_health:  {"kind": "water|sleep|exercise|steps|weight", "value": number}
- add_task:    {"text": string, "when": "ISO date or null", "priority": "low|medium|high"}
- add_event:   {"text": string, "when": "ISO datetime", "duration_minutes": number}
- create_goal: {"text": string, "when": "ISO date or null"}
- journal:     {"text": string}
- unknown:     {}

Only use "unknown" when nothing else fits. Resolve relative dates like
"tomorrow" or "next Friday" against today's date.

Return JSON only:
{"action": "...", "fields": {...}, "confidence": 0.0..1.0}

SENTENCE: $utterance
''';

  static String dailyBriefing(LifeContext context) => '''
${_dataBlock(context)}

Write this morning's briefing: at most 4 short sentences. Lead with what
actually matters today (deadlines, meetings, anything at risk), then one
observation from recent patterns, then one thing to keep an eye on.

No greeting, no motivational filler. Cite tokens where you use a specific fact.
Plain text, not JSON.
''';

  static String reflectionQuestions(LifeContext context) => '''
${_dataBlock(context)}

Write 3 evening reflection questions tailored to what actually happened today
for this person. Specific beats profound — reference real events from the data.
Never ask something the data already answers.

Return JSON only: {"questions": ["...", "...", "..."]}
''';
}
