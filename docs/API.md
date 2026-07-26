# API reference

LifeOS has no backend of its own. This document covers the three interfaces it
talks to: the `AIService` contract used by feature code, the wire formats of the
model providers, and the optional Supabase schema.

---

## 1. `AIService`

The app's entire AI surface (`lib/ai/ai_service.dart`). Feature code depends on
this and nothing else — never on a provider, a model name or an HTTP client.

Contract for every method:

- **grounded** — may only assert what is in the supplied `LifeContext`;
- **cited** — claims carry `Citation`s resolved back to real records;
- **total** — failures return `Err`, never throw.

```dart
abstract interface class AIService {
  String get providerId;
  String get model;
  bool get isRemote;

  Future<Result<AiSummary>> summarize(String text, {int maxSentences, String? instruction});
  Future<Result<MoodAnalysis>> analyzeMood(String text, {MoodEntry? selfReported});
  Future<Result<List<Insight>>> generateInsights(LifeContext context);
  Future<Result<AiAnswer>> answerQuestion(String question, LifeContext context,
      {List<String> conversationHistory});
  Stream<String> answerQuestionStream(String question, LifeContext context,
      {List<String> conversationHistory});
  Future<Result<DayPlan>> planDay({required DateTime date, required List<Task> tasks,
      required LifeContext context});
  Future<Result<ExpenseAnalysis>> analyzeExpenses({...});
  Future<Result<List<HabitSuggestion>>> suggestHabits(LifeContext context);
  Future<Result<PeriodReview>> weeklyReview(LifeContext context);
  Future<Result<PeriodReview>> monthlyReview(LifeContext context);
  Future<Result<PeriodReview>> periodReview(ReviewPeriod period, LifeContext context);
  Future<Result<GoalPlan>> planGoal(Goal goal, LifeContext context);
  Future<Result<ParsedIntent>> parseIntent(String utterance);
  Future<Result<String>> dailyBriefing(LifeContext context);
  Future<Result<List<String>>> reflectionQuestions(LifeContext context);
}
```

### `LlmClient`

The one provider-shaped abstraction. Implement three methods to add a backend.

```dart
abstract interface class LlmClient {
  String get providerId;
  String get model;
  Future<LlmCompletion> complete(LlmRequest request);
  Stream<String> stream(LlmRequest request);
  Future<bool> ping();
}
```

`LlmRequest` keeps `systemPrompt` separable from `conversation`, because
providers disagree about where the system prompt belongs.

---

## 2. Provider wire formats

What each client sends and reads. All are implemented in `lib/ai/clients/`.

### OpenAI — `POST /v1/chat/completions`

```
Authorization: Bearer <key>
{ "model", "messages": [{role, content}], "temperature", "max_tokens",
  "stream", "response_format": {"type": "json_object"} }
```
Reads `choices[0].message.content`, `usage.*`, `choices[0].finish_reason`.
Streams SSE `choices[0].delta.content`.

### Anthropic — `POST /v1/messages`

```
x-api-key: <key>
anthropic-version: 2023-06-01
{ "model", "max_tokens", "temperature", "system", "messages", "stream" }
```
Reads the concatenation of `content[].text` where `type == "text"`, plus
`usage.input_tokens` / `output_tokens` and `stop_reason`. Streams SSE
`content_block_delta.delta.text`.

### Gemini — `POST /v1beta/models/{model}:generateContent?key=`

```
{ "contents": [{role: "user"|"model", parts: [{text}]}],
  "systemInstruction": {parts: [{text}]},
  "generationConfig": {temperature, maxOutputTokens, responseMimeType} }
```
Reads `candidates[0].content.parts[].text` and `usageMetadata.*`. Streams via
`:streamGenerateContent?alt=sse`.

### Ollama — `POST /api/chat`

```
{ "model", "messages", "stream", "format": "json",
  "options": {temperature, num_predict} }
```
Reads `message.content`, `prompt_eval_count`, `eval_count`. Streams
**newline-delimited JSON**, not SSE. Timeouts are doubled: a local model is
slower to first token than a hosted API.

### Error handling

`LlmHttpErrors` maps status codes to user-facing messages and decides
retryability:

| Status | Message | Retryable |
| --- | --- | --- |
| 401 / 403 | "That API key was rejected." | no |
| 404 | "That model is not available on your account." | no |
| 413 | "That request was too large. Try a shorter time range." | no |
| 429 | "Rate limit reached." | yes |
| ≥ 500 | "The AI service is having trouble." | yes |

---

## 3. Supabase (optional)

Sync is off unless `SUPABASE_URL` and `SUPABASE_ANON_KEY` are supplied. Nine
tables mirror local ones (`SyncService._remoteTables`); anything absent stays
device-only.

| Local table | Remote table |
| --- | --- |
| `journal_entries` | `journal_entries` |
| `mood_entries` | `mood_entries` |
| `habits` | `habits` |
| `goals` | `goals` |
| `tasks` | `tasks` |
| `calendar_events` | `calendar_events` |
| `money_transactions` | `transactions` |
| `health_metrics` | `health_metrics` |
| `people` | `people` |

Payloads are the entity's `toJson()` with `user_id` added server-side-safely by
the client. Every table needs the same shape:

```sql
create table journal_entries (
  id uuid primary key,
  user_id uuid not null references auth.users on delete cascade,
  -- entity columns as jsonb or typed columns
  updated_at timestamptz default now()
);

alter table journal_entries enable row level security;

create policy "owner reads"   on journal_entries for select using (auth.uid() = user_id);
create policy "owner writes"  on journal_entries for insert with check (auth.uid() = user_id);
create policy "owner updates" on journal_entries for update using (auth.uid() = user_id);
create policy "owner deletes" on journal_entries for delete using (auth.uid() = user_id);
```

RLS is what makes the `user_id` the client sets irrelevant to security — the
policy is the enforcement point.

### Account deletion

`AuthRepositoryImpl.deleteAccount()` wipes local rows **first**, then calls an
RPC. Local-first ordering is deliberate: a failed network call must not leave a
copy on the device.

```sql
create or replace function delete_current_user() returns void
language sql security definer as $$
  delete from auth.users where id = auth.uid();
$$;
```

Cascading foreign keys remove the data rows.

### Auth

Email/password, Google and Apple, all through Supabase. Google and Apple use
`signInWithIdToken`; Apple only returns the user's name on the *first*
authorisation, so it is captured then rather than read back later.

---

## 4. Result and failure types

Every repository and service returns `Result<T>`:

```dart
sealed class Result<T> { }
final class Ok<T>  extends Result<T> { final T value; }
final class Err<T> extends Result<T> { final Failure failure; }
```

Helpers: `fold`, `map`, `flatMap`, `valueOrNull`, `failureOrNull`, `getOrElse`,
and `Result.guard` which traps thrown errors into `Failure`s.

| Failure | Retryable | Raised by |
| --- | --- | --- |
| `NetworkFailure` | yes | transport |
| `SyncFailure` | yes | outbox drain |
| `AiFailure` | depends | AI layer |
| `UnknownFailure` | yes | uncaught |
| `DatabaseFailure` | no | Drift |
| `AuthFailure` | no | sign-in |
| `PermissionFailure` | no | platform denial |
| `ValidationFailure` | no | bad input |
| `NotFoundFailure` | no | missing row |

`ErrorView` reads `isRetryable` to decide whether to offer a retry button, so
the UI never invites a user to retry something that cannot succeed.
