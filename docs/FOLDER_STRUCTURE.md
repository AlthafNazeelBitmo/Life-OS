# Folder structure

```
lib/
├── main.dart                    Entry point; opens the cache, runs the app,
│                                defers slow init until after first frame
├── app.dart                     MaterialApp.router: theme, locale, a11y overrides
│
├── core/                        Cross-cutting, no feature knowledge
│   ├── cache/                   KeyValueStore (Hive) + in-memory fake
│   ├── config/                  Env — compile-time configuration, no secrets
│   ├── di/                      Composition root: overridable providers
│   ├── error/                   Failure hierarchy, Result<T>
│   ├── extensions/              BuildContext, DateTime helpers
│   ├── l10n/                    Table-based Strings + delegate
│   ├── router/                  Routes, GoRouter, adaptive AppShell
│   ├── security/               SecureStore (keychain) + in-memory fake
│   ├── settings/                AppSettings model + controller
│   ├── theme/                   M3 themes, LifeOsTokens, colours, spacing,
│   │                            breakpoints
│   ├── utils/                   Logger, ids, formatters, statistics
│   └── widgets/                 GlassCard, StatTile, ProgressRing, state views,
│                                Entrance, AppBackdrop, SectionHeader
│
├── domain/                      Pure: no Flutter widgets, no I/O
│   ├── entities/                Freezed models + the logic that is about the
│   │                            concept (Goal.isAtRisk, Task.urgencyScore,
│   │                            Recurrence.occursOn)
│   └── repositories/            Abstract interfaces only
│
├── data/
│   ├── local/                   Drift tables, database, converters, indexer
│   ├── mappers/                 Row ↔ entity, all in one file
│   ├── remote/                  Supabase bootstrap, sync service, outbox writer
│   └── repositories/            Implementations + the Riverpod wiring that
│                                exposes them as their interfaces
│
├── ai/
│   ├── ai_service.dart          The app's entire AI surface
│   ├── ai_provider_type.dart    Which backends exist
│   ├── ai_providers.dart        Provider selection, key resolution, health
│   ├── default_ai_service.dart  Everything provider-agnostic
│   ├── offline_ai_service.dart  On-device implementation and universal fallback
│   ├── json_extractor.dart      Lenient parsing of model output
│   ├── llm_client.dart          The one provider-shaped abstraction
│   ├── clients/                 openai · gemini · anthropic · ollama · sse
│   ├── context/                 LifeContext + ContextBuilder (grounding)
│   ├── models/                  LlmRequest/Completion, AI result DTOs
│   └── prompts/                 Every prompt, in one place
│
├── features/                    One folder per feature
│   └── <feature>/
│       ├── application/         Riverpod view models
│       └── presentation/        Screens and their widgets
│
└── services/                    Platform capabilities behind interfaces
    ├── analytics/               Life score
    ├── export/                  JSON / CSV / PDF, import
    ├── notifications/           Local + push, smart scheduling
    ├── ocr/                     Receipt scanning interface + parser + stub
    ├── security/                Biometrics, encryption
    ├── voice/                   Speech → intent → repository write
    └── widgets/                 Home-screen widget data publishing
```

## Features

```
features/
├── ai_chat/         Assistant conversation + the floating button
├── auth/            Sign in/up, session, biometric lock
├── calendar/        Month/agenda calendar
├── dashboard/       Home screen and its cards
├── finance/         Money screen, budgets, analysis
├── goals/           Goals list and detail with AI planning
├── habits/          Habits list, detail, heatmap, suggestions
├── health/          Metrics and charts
├── insights/        Insights feed, life score, period reviews
├── journal/         Feed, compose, entry detail
├── mood/            Check-in, trends, correlations
├── onboarding/      Splash and first-run
├── people/          Relationship tracker
├── planner/         "Plan" tab: agenda + AI day plan
├── search/          Cross-module search
├── settings/        Settings and its four sub-screens
├── tasks/           Kanban board and list
└── timeline/        Infinite unified feed
```

## Where to put a new thing

| You are adding… | It goes in… |
| --- | --- |
| A new screen for an existing feature | `features/<feature>/presentation/` |
| Logic a screen needs | `features/<feature>/application/` as a Notifier |
| A new persisted concept | `domain/entities/` + `data/local/tables.dart` + a repository interface and impl + a line in `mappers.dart` |
| A widget used by two features | `core/widgets/` |
| A new AI capability | A method on `AIService`, a prompt in `prompt_library.dart`, and implementations in both `DefaultAiService` and `OfflineAiService` |
| A new AI provider | `ai/clients/`, one `AiProviderType` value, one line in `llmClientProvider` |
| A platform capability | `services/<area>/`, behind an interface with a fake |

## Tests mirror the source

```
test/
├── unit/            Pure logic: Result, Recurrence, Stats, JsonExtractor,
│                    OfflineAiService, ReceiptParser
├── repository/      Real in-memory SQLite, no mocks
└── widget/          Shared widgets and the settings/AI wiring

integration_test/
└── app_test.dart    First-run flows end to end
```
