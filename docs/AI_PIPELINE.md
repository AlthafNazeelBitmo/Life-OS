# The AI pipeline

## The problem this solves

A personal assistant that invents a number is worse than no assistant. If
LifeOS says "you spent £340 on takeaways last month" it has to be true, and the
user has to be able to check it. That constraint drives the whole design.

## Request lifecycle

```mermaid
flowchart LR
    Q[Question or task] --> CB[ContextBuilder]
    CB -->|retrieval or window| LC[LifeContext<br/>chunks + aggregates]
    LC --> PB[Prompt library]
    PB --> C[LlmClient]
    C --> M[(Provider)]
    M --> RESP[Raw text]
    RESP --> JX[Lenient JSON / token extraction]
    JX --> RES[Resolve tokens to real records]
    RES --> OUT[Typed result + Citations + confidence]
```

### 1. Build the grounding set

`ContextBuilder` produces a `LifeContext`: a list of `ContextChunk`s, each with a
short token (`j3`, `h1`, `m12`), and a map of pre-computed aggregates.

Two strategies, deliberately different:

- **`forRange`** — exhaustive within a window. Used for reviews and insights,
  where missing a week would change the conclusion.
- **`forQuestion`** — retrieval. Searches the index, hydrates only what matched,
  then appends a short recency window so questions about "this week" work even
  when no keyword matched.

Both cap what they emit. An oversized prompt is slower, costs more, and
measurably degrades answer quality — the budget is a feature, not a limitation.

### 2. Aggregates come from SQL, never from the model

Totals, averages, streaks and correlations are computed on-device and handed to
the model as facts it must trust. Models are bad at arithmetic over long lists
and confidently wrong when they get it wrong. `analyzeExpenses` is the clearest
example: the model writes the narrative, but every figure in the result object
comes from the database.

This is also why the on-device provider is not a downgrade in accuracy. It
reports the same numbers; it just does not write prose about them.

### 3. Prompting

All prompts live in `lib/ai/prompts/prompt_library.dart`. The shared system
preamble states the two non-negotiables — assert only what is in the data, cite
with bracket tokens — so no task prompt has to restate them.

### 4. Parsing is lenient on purpose

`JsonExtractor` degrades in stages: strict decode → fenced code block → first
balanced object (brace-matching that ignores braces inside strings) → give up.
Models wrap JSON in prose even when told not to, and treating that as a hard
failure surfaces to the user as "the AI is broken" for an answer that was
perfectly parseable.

### 5. Citations are verified, not trusted

The app extracts every `[token]` the model used, looks each one up in the
`LifeContext` it supplied, and keeps only those that resolve.

- Tokens that do not resolve **lower the answer's confidence** proportionally.
- An insight with **no** resolved citations is capped below the threshold at
  which the UI presents it as fact — it renders as "possible pattern".
- Resolved citations become tappable chips that deep-link to the record.

This is what makes "never hallucinate, always cite" enforceable rather than
aspirational.

### 6. Failure has a floor

`DefaultAiService` wraps every call: one retry on transient errors, then a fall
back to `OfflineAiService`. A user whose key expired mid-month still gets
summaries, search answers, day plans and reviews — plainer, but working.

## Adding a provider

Three steps, none in feature code:

1. Add a value to `AiProviderType` (id, label, whether it needs a key, whether
   it streams).
2. Implement `LlmClient` — `complete`, `stream`, `ping`. The `LlmHttpErrors`
   mixin already maps status codes to messages worth showing a user and decides
   what is retryable.
3. Add one line to the `switch` in `llmClientProvider`.

`LlmRequest` keeps the system prompt separable from the conversation because
providers disagree about where it goes: a top-level field for Anthropic and
Gemini, a message for OpenAI.

## The nine `AIService` methods

| Method | Grounded on | Returns |
| --- | --- | --- |
| `summarize` | Supplied text only | `AiSummary` |
| `analyzeMood` | Entry text + optional self-rating | `MoodAnalysis` |
| `generateInsights` | Window context + on-device correlations | `List<Insight>` |
| `answerQuestion` | Retrieval context | `AiAnswer` with citations |
| `planDay` | Today's tasks + calendar + energy patterns | `DayPlan` |
| `analyzeExpenses` | SQL totals + detected subscriptions | `ExpenseAnalysis` |
| `suggestHabits` | Journal, goals, sleep, mood | `List<HabitSuggestion>` |
| `weeklyReview` / `monthlyReview` | Period window | `PeriodReview` |
| `parseIntent` | The spoken sentence | `ParsedIntent` |

Plus `planGoal`, `dailyBriefing`, `reflectionQuestions` and a streaming variant
of `answerQuestion` for the chat screen.

## Privacy

Three independent switches, all of which land in the same place —
`llmClientProvider` returns `null` and the app uses the on-device service:

1. **Assistant off** — no AI features at all, including summaries.
2. **Share data off** — a saved key does not override an explicit privacy
   choice.
3. **Provider = on-device or Ollama** — nothing leaves the device or the local
   network.

API keys live in the platform keychain (`SecureStore`), never in the Drift file,
and are excluded from every export. What a remote provider receives is the
chunks needed for the question asked — never the whole history.

## Testing the pipeline

`OfflineAiService` is fully unit-tested (intent parsing, sentiment, extractive
summarising, retrieval answers) because it runs everywhere with no network.
`JsonExtractor` is tested against the malformed shapes models actually produce.
For model-backed paths, inject a fake `LlmClient` — `DefaultAiService` takes one
in its constructor precisely so no test needs a network or a key.
