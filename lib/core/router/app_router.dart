import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai_chat/presentation/chat_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/lock_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/sign_up_screen.dart';
import '../../features/calendar/presentation/calendar_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/finance/presentation/money_screen.dart';
import '../../features/goals/presentation/goal_detail_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/habits/presentation/habit_detail_screen.dart';
import '../../features/habits/presentation/habits_screen.dart';
import '../../features/health/presentation/health_screen.dart';
import '../../features/insights/presentation/insights_screen.dart';
import '../../features/insights/presentation/review_screen.dart';
import '../../features/journal/presentation/journal_compose_screen.dart';
import '../../features/journal/presentation/journal_entry_screen.dart';
import '../../features/journal/presentation/journal_screen.dart';
import '../../features/mood/presentation/mood_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/people/presentation/people_screen.dart';
import '../../features/people/presentation/person_detail_screen.dart';
import '../../features/planner/presentation/plan_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/presentation/ai_settings_screen.dart';
import '../../features/settings/presentation/data_settings_screen.dart';
import '../../features/settings/presentation/notification_settings_screen.dart';
import '../../features/settings/presentation/privacy_settings_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/tasks/presentation/tasks_screen.dart';
import '../../features/timeline/presentation/timeline_screen.dart';
import '../settings/settings_controller.dart';
import 'app_routes.dart';
import 'app_shell.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

/// Builds the app's single [GoRouter].
///
/// Redirects are centralised here rather than scattered across screens, so the
/// answer to "can the user be on this page right now?" lives in one function.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final settings = ref.read(settingsProvider);
      final location = state.matchedLocation;

      // Wait for the session restore to finish before deciding anything.
      if (auth.isLoading) {
        return location == Routes.splash ? null : Routes.splash;
      }

      final signedIn = auth.value?.isAuthenticated ?? false;
      final locked = auth.value?.isLocked ?? false;

      if (!settings.onboardingComplete) {
        return location == Routes.onboarding ? null : Routes.onboarding;
      }

      final atAuthScreen =
          location == Routes.signIn || location == Routes.signUp;

      if (!signedIn) {
        return atAuthScreen ? null : Routes.signIn;
      }

      // Biometric gate sits between a valid session and the app content.
      if (locked) {
        return location == Routes.lock ? null : Routes.lock;
      }

      if (atAuthScreen ||
          location == Routes.splash ||
          location == Routes.lock ||
          location == Routes.onboarding) {
        return Routes.dashboard;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: Routes.lock,
        builder: (context, state) => const LockScreen(),
      ),

      // --- Main shell: five persistent tabs -----------------------------
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.journal,
                builder: (context, state) => const JournalScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.plan,
                builder: (context, state) => const PlanScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.money,
                builder: (context, state) => const MoneyScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.insights,
                builder: (context, state) => const InsightsScreen(),
              ),
            ],
          ),
        ],
      ),

      // --- Pushed over the shell ----------------------------------------
      GoRoute(
        path: '${Routes.journalEntry}/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            JournalEntryScreen(entryId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.journalCompose,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            JournalComposeScreen(entryId: state.uri.queryParameters['id']),
      ),
      GoRoute(
        path: Routes.mood,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const MoodScreen(),
      ),
      GoRoute(
        path: Routes.habits,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const HabitsScreen(),
      ),
      GoRoute(
        path: '${Routes.habitDetail}/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            HabitDetailScreen(habitId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.goals,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const GoalsScreen(),
      ),
      GoRoute(
        path: '${Routes.goalDetail}/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            GoalDetailScreen(goalId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.tasks,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const TasksScreen(),
      ),
      GoRoute(
        path: Routes.calendar,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CalendarScreen(),
      ),
      GoRoute(
        path: Routes.health,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const HealthScreen(),
      ),
      GoRoute(
        path: Routes.people,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PeopleScreen(),
      ),
      GoRoute(
        path: '${Routes.personDetail}/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            PersonDetailScreen(personId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.timeline,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const TimelineScreen(),
      ),
      GoRoute(
        path: Routes.search,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            SearchScreen(initialQuery: state.uri.queryParameters['q'] ?? ''),
      ),
      GoRoute(
        path: Routes.chat,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            ChatScreen(seedPrompt: state.uri.queryParameters['prompt']),
      ),
      GoRoute(
        path: '${Routes.review}/:period',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            ReviewScreen(periodId: state.pathParameters['period']!),
      ),
      GoRoute(
        path: Routes.settings,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'ai',
            builder: (context, state) => const AiSettingsScreen(),
          ),
          GoRoute(
            path: 'privacy',
            builder: (context, state) => const PrivacySettingsScreen(),
          ),
          GoRoute(
            path: 'notifications',
            builder: (context, state) => const NotificationSettingsScreen(),
          ),
          GoRoute(
            path: 'data',
            builder: (context, state) => const DataSettingsScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(child: Text('No screen for ${state.uri}')),
    ),
  );
});

/// Bridges Riverpod state into GoRouter's [Listenable]-based refresh.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    _subscriptions = <ProviderSubscription<Object?>>[
      ref.listen(authControllerProvider, (_, __) => notifyListeners()),
      ref.listen(
        settingsProvider.select((s) => s.onboardingComplete),
        (_, __) => notifyListeners(),
      ),
    ];
  }

  late final List<ProviderSubscription<Object?>> _subscriptions;

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    super.dispose();
  }
}
