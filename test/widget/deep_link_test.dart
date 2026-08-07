import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeos/core/cache/key_value_store.dart';
import 'package:lifeos/core/di/core_providers.dart';
import 'package:lifeos/core/router/app_router.dart';
import 'package:lifeos/core/router/app_routes.dart';
import 'package:lifeos/core/security/secure_store.dart';
import 'package:lifeos/data/local/app_database.dart';

/// Notification payloads are just strings, and a string that no longer matches
/// a route fails silently at the worst possible moment — when the user taps a
/// reminder. These tests keep the allow-list and the route table honest about
/// each other.
void main() {
  test('every deep-link target resolves to a route with no parameters', () {
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider
            .overrideWithValue(AppDatabase.forTesting(NativeDatabase.memory())),
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        secureStoreProvider.overrideWithValue(InMemorySecureStore()),
      ],
    );
    addTearDown(container.dispose);

    final registered = _pathsOf(container.read(routerProvider));

    for (final target in Routes.deepLinkTargets) {
      expect(
        registered,
        contains(target),
        reason: '$target is offered as a notification target but is not a '
            'route — tapping that reminder would land on the error page',
      );
    }
  });

  test('unknown targets are refused', () {
    expect(Routes.isDeepLinkable(Routes.dashboard), isTrue);
    // Detail routes need an id, so the bare path must not be accepted.
    expect(Routes.isDeepLinkable(Routes.journalEntry), isFalse);
    // A push payload is remote input and can be anything at all.
    expect(Routes.isDeepLinkable('/../etc/passwd'), isFalse);
    expect(Routes.isDeepLinkable('https://example.com'), isFalse);
    expect(Routes.isDeepLinkable(''), isFalse);
  });

  test('the lock screen is not a deep-link target', () {
    // Not a security boundary on its own — `redirect` is — but nothing should
    // be inviting the user there, and nothing should be sending them past it.
    expect(Routes.deepLinkTargets, isNot(contains(Routes.lock)));
    expect(Routes.deepLinkTargets, isNot(contains(Routes.signIn)));
  });
}

/// Full paths of every parameterless [GoRoute] in the tree.
Set<String> _pathsOf(GoRouter router) {
  final paths = <String>{};

  void walk(List<RouteBase> routes, String prefix) {
    for (final route in routes) {
      var full = prefix;
      if (route is GoRoute) {
        full = route.path.startsWith('/')
            ? route.path
            : '${prefix == '/' ? '' : prefix}/${route.path}';
        if (!full.contains(':')) paths.add(full);
      }
      walk(route.routes, full);
    }
  }

  walk(router.configuration.routes, '');
  return paths;
}
