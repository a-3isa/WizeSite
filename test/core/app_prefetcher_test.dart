import 'dart:async';

import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('warmDashboard primes dashboard, subscription, usage, and settings', () {
    final warmed = <AppPrefetchTarget>[];
    final prefetcher = AppPrefetcher(
      warm: ({required target, projectId}) {
        warmed.add(target);
      },
    );

    prefetcher.warmDashboard();

    expect(warmed, [
      AppPrefetchTarget.dashboardSummary,
      AppPrefetchTarget.currentSubscription,
      AppPrefetchTarget.currentUsage,
      AppPrefetchTarget.currentUserSettings,
    ]);
  });

  test('warmAddEntry primes projects and workers before opening forms', () {
    final warmed = <AppPrefetchTarget>[];
    final prefetcher = AppPrefetcher(
      warm: ({required target, projectId}) {
        warmed.add(target);
      },
    );

    prefetcher.warmAddEntry();

    expect(warmed, [
      AppPrefetchTarget.projects,
      AppPrefetchTarget.workers,
      AppPrefetchTarget.currentUserSettings,
    ]);
  });

  test('warmReports primes reportable project selection', () {
    final warmed = <AppPrefetchTarget>[];
    final prefetcher = AppPrefetcher(
      warm: ({required target, projectId}) => warmed.add(target),
    );

    prefetcher.warmReports();

    expect(warmed, [AppPrefetchTarget.allProjects]);
  });

  test('warmProjectReport carries the target project id', () {
    final calls = <({AppPrefetchTarget target, String? projectId})>[];
    final prefetcher = AppPrefetcher(
      warm: ({required target, projectId}) {
        calls.add((target: target, projectId: projectId));
      },
    );

    prefetcher.warmProjectReport('project_1');

    expect(calls, [
      (target: AppPrefetchTarget.reportMetrics, projectId: 'project_1'),
    ]);
  });

  test('dedupes matching warm calls while the first call is active', () async {
    final completions = <AppPrefetchTarget, Completer<void>>{};
    final warmed = <AppPrefetchTarget>[];
    final prefetcher = AppPrefetcher(
      warm: ({required target, projectId}) {
        warmed.add(target);
        return completions.putIfAbsent(target, () => Completer<void>()).future;
      },
    );

    prefetcher.warmSettings();
    prefetcher.warmSettings();

    expect(warmed, [
      AppPrefetchTarget.currentUserSettings,
      AppPrefetchTarget.currentSubscription,
    ]);

    for (final completion in completions.values) {
      completion.complete();
    }
    await Future<void>.delayed(Duration.zero);

    prefetcher.warmSettings();

    expect(warmed, [
      AppPrefetchTarget.currentUserSettings,
      AppPrefetchTarget.currentSubscription,
      AppPrefetchTarget.currentUserSettings,
      AppPrefetchTarget.currentSubscription,
    ]);
  });

  test('warmCritical primes all six critical targets', () async {
    final warmed = <AppPrefetchTarget>[];
    final prefetcher = AppPrefetcher(
      warm: ({required target, projectId}) {
        warmed.add(target);
      },
    );

    await prefetcher.warmCritical();

    expect(
      warmed,
      containsAll([
        AppPrefetchTarget.dashboardSummary,
        AppPrefetchTarget.currentSubscription,
        AppPrefetchTarget.currentUsage,
        AppPrefetchTarget.currentUserSettings,
        AppPrefetchTarget.projects,
        AppPrefetchTarget.workers,
      ]),
    );
    expect(warmed, hasLength(6));
  });

  test(
    'warmCritical returns a future that resolves when all warms complete',
    () async {
      final completers = <AppPrefetchTarget, Completer<void>>{};
      final prefetcher = AppPrefetcher(
        warm: ({required target, projectId}) {
          return completers.putIfAbsent(target, Completer<void>.new).future;
        },
      );

      var resolved = false;
      unawaited(prefetcher.warmCritical().then((_) => resolved = true));

      await Future<void>.delayed(Duration.zero);
      expect(resolved, isFalse);

      for (final c in completers.values) {
        c.complete();
      }
      await Future<void>.delayed(Duration.zero);
      expect(resolved, isTrue);
    },
  );

  test(
    'warmCritical resolves after timeout even when warms are still pending',
    () {
      fakeAsync((fake) {
        final prefetcher = AppPrefetcher(
          warm: ({required target, projectId}) => Completer<void>().future,
        );
        var resolved = false;
        unawaited(prefetcher.warmCritical().then((_) => resolved = true));

        fake.elapse(const Duration(seconds: 4));
        expect(resolved, isFalse);

        fake.elapse(const Duration(seconds: 2));
        expect(resolved, isTrue);
      });
    },
  );
}
