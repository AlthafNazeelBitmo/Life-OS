# State management

Riverpod does two jobs here: dependency injection and state. Using one tool for
both is what makes a test able to swap the database for an in-memory one and get
a fully wired app for free.

## The composition root

Providers with real I/O are declared in `core/di/core_providers.dart` as
unimplemented, and overridden **once**, in `main()`:

```dart
runApp(
  ProviderScope(
    overrides: [keyValueStoreProvider.overrideWithValue(store)],
    child: const LifeOsApp(),
  ),
);
```

A test overrides the same handful:

```dart
ProviderContainer(overrides: [
  keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
  secureStoreProvider.overrideWithValue(InMemorySecureStore()),
  appDatabaseProvider.overrideWithValue(AppDatabase.forTesting(NativeDatabase.memory())),
]);
```

Nothing else in the tree changes, because everything downstream depends on the
interface, not the implementation.

## Which provider type, and when

| Type | Use for | Example |
| --- | --- | --- |
| `Provider` | Stateless services and repositories | `journalRepositoryProvider` |
| `StreamProvider` | A live query from Drift | `todayHabitsProvider` |
| `FutureProvider` | A one-shot async read | `journalStreakProvider` |
| `Notifier` | Synchronous state with commands | `SettingsController` |
| `AsyncNotifier` | Async state with commands | `DashboardController`, `AuthController` |
| `.family` | Parameterised reads | `journalEntryProvider(id)` |

Repositories are always exposed as their **interface**:

```dart
final Provider<JournalRepository> journalRepositoryProvider =
    Provider<JournalRepository>((ref) => JournalRepositoryImpl(...));
```

Feature code that named `JournalRepositoryImpl` would defeat the whole
arrangement.

## Reads are streams

The single most important convention: **a write never returns the new list**.
It reports success or failure, and the UI updates because the Drift stream
emitted.

```dart
Stream<List<JournalEntry>> watchEntries({int limit, int offset});
Future<Result<JournalEntry>> upsert(JournalEntry entry);
```

That is why logging a habit by voice repaints the dashboard ring without either
feature knowing the other exists.

Where a derived view depends on two tables, the stream must depend on both.
Drift's `readsFrom` is how that is declared:

```dart
_db.customSelect(
  'SELECT 1',
  readsFrom: {_db.habits, _db.habitLogs},
).watch().asyncMap((_) async => ...);
```

Without the second table listed, checking off a habit would not repaint the row.

## Rebuild discipline

**Select the slice you need.** Watching a whole settings object to read one flag
rebuilds on every unrelated change:

```dart
// rebuilds when the currency changes too
final settings = ref.watch(settingsProvider);

// rebuilds only when the theme changes
final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
```

Common selectors are pre-declared (`themeModeProvider`, `currencyProvider`) so
call sites do not each re-derive them.

**Compose from several small providers, not one big one.** The dashboard reads
six independent stream providers. A change to today's mood does not re-query
calendar events.

**Read in callbacks, watch in build.** `ref.watch` inside an event handler
subscribes something that is about to be discarded.

## Async state and stale data

`AsyncValue` is used as intended: while refreshing, Riverpod keeps the previous
value, and `AsyncView` renders it rather than flashing a spinner.

```dart
if (value.hasValue) return builder(context, value.requireValue);
```

Screens are consistent about the three states: skeleton placeholders where the
shape is known, `ErrorView` (which offers retry only for retryable failures),
and `EmptyState` with an action.

## View models

`AsyncNotifier` for anything with async state:

```dart
class DashboardController extends AsyncNotifier<DashboardData> {
  @override
  Future<DashboardData> build() async {
    final habits = await ref.watch(_todayHabitsProvider.future);
    // ... compose the rest
  }

  Future<void> toggleHabit(String id, {required bool done}) async {
    await ref.read(habitRepositoryProvider).log(id, DateTime.now(),
        amount: done ? 1 : 0);
  }
}
```

Note what the command does *not* do: it does not update `state`. The write goes
to the repository, the stream emits, and `build` runs again. One source of
truth.

## Lifecycle

`AuthController` mixes in `WidgetsBindingObserver` to re-arm the biometric lock
after the app has been backgrounded for more than two minutes. A grace period
matters: a lock that fires when the user flips to their authenticator app and
straight back is a lock people turn off.

Disposal is explicit where it matters:

```dart
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
```

## Router integration

`GoRouter` needs a `Listenable`; `_RouterRefresh` bridges Riverpod to it by
listening to auth state and the onboarding flag. All redirect logic lives in one
`redirect` function, so "can the user be on this page right now?" has exactly
one answer, rather than a guard scattered across twenty screens.

## Testing

- **Unit** — construct a `ProviderContainer` with fakes; no widgets involved.
- **Repository** — real in-memory SQLite. The behaviour worth testing lives in
  the SQL, and a mocked database would verify nothing about it.
- **Widget** — `ProviderScope` with the same overrides plus a real theme.
- **Integration** — `UncontrolledProviderScope` around the real app with
  in-memory storage, so the suite is hermetic.
