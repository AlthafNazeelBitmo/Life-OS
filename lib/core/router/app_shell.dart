import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai_chat/presentation/widgets/assistant_fab.dart';
import '../extensions/context_x.dart';
import '../theme/breakpoints.dart';
import 'app_routes.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_Destination> _destinations = <_Destination>[
  _Destination('Home', Icons.dashboard_outlined, Icons.dashboard_rounded),
  _Destination('Journal', Icons.menu_book_outlined, Icons.menu_book_rounded),
  _Destination('Plan', Icons.event_note_outlined, Icons.event_note_rounded),
  _Destination(
    'Money',
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet_rounded,
  ),
  _Destination('Insights', Icons.insights_outlined, Icons.insights_rounded),
];

/// Adaptive chrome around the five main tabs.
///
/// One widget tree serves every form factor: bottom navigation on phones, a
/// rail on tablets, and an extended rail on desktop. The assistant button
/// floats above all of them because it is reachable from anywhere in the app.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _go(int index) => navigationShell.goBranch(
        index,
        // Tapping the active tab pops that branch back to its root.
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;
    final useRail = size != WindowSize.compact;

    final content = Stack(
      children: <Widget>[
        navigationShell,
        const Positioned(right: 16, bottom: 16, child: AssistantFab()),
      ],
    );

    if (!useRail) {
      return Scaffold(
        body: content,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _go,
          destinations: <Widget>[
            for (final destination in _destinations)
              NavigationDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: destination.label,
                tooltip: destination.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _go,
            extended: size == WindowSize.large,
            minExtendedWidth: 190,
            leading: const _RailLeading(),
            trailing: const Expanded(child: _RailTrailing()),
            destinations: <NavigationRailDestination>[
              for (final destination in _destinations)
                NavigationRailDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: Text(destination.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _RailLeading extends StatelessWidget {
  const _RailLeading();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: IconButton.filledTonal(
          tooltip: 'Search everything',
          onPressed: () => context.push(Routes.search),
          icon: const Icon(Icons.search_rounded),
        ),
      );
}

class _RailTrailing extends StatelessWidget {
  const _RailTrailing();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Timeline',
                onPressed: () => context.push(Routes.timeline),
                icon: const Icon(Icons.timeline_rounded),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => context.push(Routes.settings),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
      );
}
