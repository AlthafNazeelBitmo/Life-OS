import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/breakpoints.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../application/dashboard_controller.dart';
import 'widgets/dashboard_cards.dart';
import 'widgets/quick_add_bar.dart';

/// The home screen: one card per life area, ordered by what needs attention.
///
/// The layout is a responsive masonry grid — one column on a phone, up to four
/// on desktop — so the same card widgets serve every form factor.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Generated after first paint: the dashboard must be usable before the
    // assistant has anything to say.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dashboardControllerProvider.notifier).refreshBriefing();
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dashboardControllerProvider);
    final user = ref.watch(currentUserProvider);

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardControllerProvider);
            await ref
                .read(dashboardControllerProvider.notifier)
                .refreshBriefing(force: true);
          },
          child: AsyncView<DashboardData>(
            value: async,
            loading: const _DashboardSkeleton(),
            onRetry: () => ref.invalidate(dashboardControllerProvider),
            builder: (context, data) => CustomScrollView(
              slivers: <Widget>[
                SliverAppBar.large(
                  backgroundColor: Colors.transparent,
                  // Single line only. SliverAppBar.large scales its title by
                  // 1.5x and animates it between the expanded and collapsed
                  // positions; a multi-line title collides with the toolbar on
                  // the way up. The date lives in the body instead.
                  title: Text(
                    '${data.greeting}${user == null ? '' : ', ${user.firstName}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  actions: <Widget>[
                    IconButton(
                      tooltip: 'Search everything',
                      onPressed: () => context.push(Routes.search),
                      icon: const Icon(Icons.search_rounded),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: () => context.push(Routes.settings),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
                    child: Text(
                      Fmt.longDate(data.date),
                      style: context.text.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: QuickAddBar()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.lg,
                    Gap.lg,
                    Gap.lg,
                    120,
                  ),
                  sliver: _CardGrid(data: data),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final columns = Breakpoints.gridColumns(context.screenSize.width);

    final cards = <Widget>[
      BriefingCard(summary: data.aiSummary),
      MoodCard(mood: data.mood),
      HabitRingCard(habits: data.habits, completion: data.habitCompletion),
      TasksCard(tasks: data.tasks),
      UpcomingCard(events: data.events),
      MoneyCard(spentTodayMinor: data.spentTodayMinor),
      HealthCard(summary: data.health),
      LifeScoreCard(journalStreak: data.journalStreak, goals: data.goals),
    ];

    if (columns == 1) {
      return SliverList.separated(
        itemCount: cards.length,
        separatorBuilder: (_, __) => Gap.h16,
        itemBuilder: (context, index) =>
            Entrance(index: index, child: cards[index]),
      );
    }

    // A simple column-balanced masonry: cards keep their natural height instead
    // of being stretched to a uniform grid cell.
    final columnChildren = List<List<Widget>>.generate(columns, (_) => <Widget>[]);
    for (var i = 0; i < cards.length; i++) {
      columnChildren[i % columns].add(
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.lg),
          child: Entrance(index: i, child: cards[i]),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: Breakpoints.maxContentWidth,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var column = 0; column < columns; column++) ...<Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: columnChildren[column],
                  ),
                ),
                if (column < columns - 1) Gap.w16,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: <Widget>[
          const SkeletonBox(height: 34, width: 220),
          Gap.h8,
          const SkeletonBox(height: 16, width: 160),
          Gap.h24,
          for (var i = 0; i < 4; i++) ...<Widget>[
            SkeletonBox(height: i.isEven ? 148 : 108, radius: Radii.lg),
            Gap.h16,
          ],
        ],
      );
}

/// Accent colours used across the dashboard cards, kept together so the set
/// reads as one palette rather than eight unrelated choices.
abstract final class DashboardAccents {
  const DashboardAccents._();

  static const Color briefing = AppColors.insights;
  static const Color mood = AppColors.mood;
  static const Color habits = AppColors.habits;
  static const Color tasks = AppColors.tasks;
  static const Color calendar = AppColors.calendar;
  static const Color money = AppColors.finance;
  static const Color health = AppColors.health;
  static const Color goals = AppColors.goals;
}
