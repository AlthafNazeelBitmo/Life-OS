# LifeOS

An AI-powered personal operating system, built with Flutter. One app that
replaces notes, journal, habit tracker, calendar, expenses, mood log, goals and
a personal assistant — and, because those live in one database, can say things
none of them could say alone:

> *"Your focus scores are 1.8 points higher on days you exercised before noon
> [h3][m12], and you have done that on 4 of the last 14 days [h3]."*

**Offline-first, private by default, and useful with no AI account at all.**

---

## What it does

| Module | What it gives you |
| --- | --- |
| **Journal** | Text, photos, voice notes, location, weather, tags, people. AI summarises, names the emotions, extracts events and builds a life timeline. |
| **Mood** | Six dimensions (happiness, energy, focus, productivity, stress, anxiety), charted, with on-device correlation against habits, sleep and journalling. |
| **Habits** | Daily / weekly / monthly / custom schedules, streaks, completion heatmap, a 0–100 habit score, and AI suggestions grounded in your own records. |
| **Goals** | Long and short term, milestones, deadlines, at-risk detection, and an AI breakdown into daily tasks, a weekly plan and a monthly roadmap. |
| **Tasks** | Subtasks, priorities, labels, recurrence, reminders, a Kanban board with drag-and-drop, and AI prioritisation that shows its reasoning. |
| **Calendar** | Month/week/agenda views, recurring events expanded on read, birthdays synced from the relationship tracker, free-slot finding for focus blocks. |
| **Money** | Income, expenses, categories, budgets, savings goals, recurring-charge detection, receipt OCR (opt-in), and monthly analysis. |
| **Health** | Weight, water, sleep, exercise, steps, calories, resting HR, screen time — charted against your own targets. |
| **Assistant** | Chat grounded in your data, with a citation on every claim. Floating button; hold to speak. |
| **Insights** | Weekly, monthly, quarterly and yearly reviews; patterns; a life score built from five pillars. |
| **Timeline** | One infinite feed mixing journal, photos, milestones, meetings, expenses and memories. |
| **Search** | Instant lexical search across every module, offline, plus natural-language questions on top. |
| **People** | The details you always forget, interaction history, follow-up nudges, birthdays. |

Plus: morning briefing, evening reflection, "on this day" memories, home-screen
widgets, encrypted backups, biometric lock, and full JSON/CSV/PDF export.

---

## Two commitments the code actually keeps

**1. It works with no AI provider.** `OfflineAiService` is the default and the
fallback for every other provider. It is not a stub: the statistics it reports
are the same ones a model-backed service is handed, so your numbers are
identical either way — only the prose is plainer. Voice capture ("I spent 25 on
lunch") is parsed on-device with regexes and works on a plane.

**2. It does not make things up.** Every AI request is built from a
`LifeContext` — a bundle of your own records, each with a short token. The
prompt permits only claims backed by those tokens, and the app resolves the
tokens the model cited back to real rows. Tokens that do not resolve lower the
answer's confidence, and an uncited insight is capped below the threshold at
which the UI presents it as fact. The citation chips under an answer are
tappable: they deep-link to the record.

---

## Getting started

```bash
git clone <this repo> && cd Life-OS
./tool/bootstrap.sh
flutter run
```

`bootstrap.sh` generates the native platform folders with your Flutter version,
fetches packages, and runs code generation. Platform folders are not vendored
on purpose — `flutter create` emits them correctly for whatever toolchain you
have, which avoids stale Gradle and CocoaPods pins.

Requires **Flutter 3.32+ / Dart 3.8+**.

### Running it

LifeOS starts with zero configuration: it uses the on-device account and the
on-device AI provider. To wire up a backend or a model, copy
`tool/dart_define.example.json` to `tool/dart_define.json` (git-ignored), fill
in what you want, and:

```bash
flutter run --dart-define-from-file=tool/dart_define.json
```

Every key is optional. **Nothing secret belongs in source** — API keys the user
enters in Settings go to the platform keychain and take precedence over
compile-time defaults.

### Code generation

Drift, Freezed and json_serializable generate `*.g.dart` / `*.freezed.dart`,
which are git-ignored. After changing an entity or a table:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

### Tests

```bash
flutter test                                  # unit, repository and widget
flutter test integration_test                 # end-to-end, needs a device
flutter test --coverage
```

Repository tests run against real in-memory SQLite rather than mocks — the
behaviour worth testing there (streak arithmetic, soft deletes, index
consistency) lives in the SQL.

---

## Architecture at a glance

```
Presentation  ── screens + Riverpod view models
     │ watches
Domain        ── entities, repository interfaces, AIService   ← no Flutter, no I/O
     │ implemented by
Data          ── Drift (source of truth), Hive cache, Supabase replica
```

Clean Architecture with MVVM in the presentation layer, the repository pattern
across the data boundary, and Riverpod as both DI container and state manager.
The domain layer names no package from `data/`, which is what lets a test swap
a repository for a fake with one `overrideWithValue`.

Full detail: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

| Document | Contents |
| --- | --- |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Layers, data flow, sync model, diagrams |
| [FOLDER_STRUCTURE.md](docs/FOLDER_STRUCTURE.md) | Where everything lives and why |
| [STATE_MANAGEMENT.md](docs/STATE_MANAGEMENT.md) | Riverpod conventions, rebuild discipline |
| [DATABASE_SCHEMA.md](docs/DATABASE_SCHEMA.md) | Tables, indexes, migrations |
| [AI_PIPELINE.md](docs/AI_PIPELINE.md) | Grounding, citations, prompts, adding a provider |
| [API.md](docs/API.md) | AIService contract, provider wire formats, Supabase schema |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Permissions, signing, store submission, widgets, OCR |

---

## Tech stack

Flutter · Riverpod · GoRouter · Drift (SQLite) · Hive · Supabase · Firebase
Messaging · flutter_local_notifications · Freezed · json_serializable ·
fl_chart · Material 3.

AI providers: **OpenAI**, **Gemini**, **Anthropic**, **Ollama** (local), and the
built-in on-device implementation. Adding a fifth is one enum value, one
`LlmClient`, one line in a factory — no feature code changes.

---

## Project status and honest limitations

This is a complete, runnable foundation built to be extended, and a few things
are deliberately marked rather than hidden:

- **Receipt OCR ships behind an interface with a stub implementation.** ML Kit
  adds ~30 MB to an Android build, so it is opt-in. The parser that turns OCR
  text into a transaction is real and unit-tested; enabling recognition is a
  dependency change, not a rewrite. See `docs/DEPLOYMENT.md`.
- **Sync is last-write-wins per record.** LifeOS is single-user, so the device
  that wrote most recently is right. A CRDT would be the wrong complexity here;
  the trade-off is written up in `docs/ARCHITECTURE.md`.
- **Search is lexical, not semantic.** It is instant, works offline, and needs
  no model. Swapping in SQLite FTS5 or embeddings is contained behind
  `SearchRepository`.
- **Home-screen widgets need native views.** The Dart side publishes every value
  the widgets read; the Android/iOS widget UIs are platform code and are
  scaffolded by `flutter create`. Keys and setup are in `HomeWidgetService`.
- **Localisation covers app chrome**, with a table-based implementation so a
  translator can add a language by appending one map. Keys map 1:1 to ARB for a
  later `gen-l10n` migration.
- **Backup encryption derives its key with salted SHA-256.** PBKDF2 is the right
  answer for a production release and is a drop-in change; the current choice is
  called out in `EncryptionService` and `docs/DEPLOYMENT.md`.

## Licence

MIT.
