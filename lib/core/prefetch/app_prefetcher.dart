import 'dart:async';

import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppPrefetchTarget {
  dashboardSummary,
  currentSubscription,
  currentUsage,
  currentUserSettings,
  projects,
  allProjects,
  workers,
  reportMetrics,
}

typedef AppPrefetchWarm =
    FutureOr<void> Function({
      required AppPrefetchTarget target,
      String? projectId,
    });

class AppPrefetcher {
  AppPrefetcher({required AppPrefetchWarm warm}) : _warm = warm;

  final AppPrefetchWarm _warm;
  final Map<String, Future<void>> _inFlight = {};

  void _warmOnce({required AppPrefetchTarget target, String? projectId}) {
    final key = '${target.name}:${projectId ?? ''}';
    if (_inFlight.containsKey(key)) {
      return;
    }
    final future = Future<void>.sync(
      () => _warm(target: target, projectId: projectId),
    );
    _inFlight[key] = future;
    unawaited(future.whenComplete(() => _inFlight.remove(key)));
  }

  void warmDashboard() {
    _warmOnce(target: AppPrefetchTarget.dashboardSummary);
    _warmOnce(target: AppPrefetchTarget.currentSubscription);
    _warmOnce(target: AppPrefetchTarget.currentUsage);
    _warmOnce(target: AppPrefetchTarget.currentUserSettings);
  }

  void warmAddEntry() {
    _warmOnce(target: AppPrefetchTarget.projects);
    _warmOnce(target: AppPrefetchTarget.workers);
    _warmOnce(target: AppPrefetchTarget.currentUserSettings);
  }

  void warmProjects() {
    _warmOnce(target: AppPrefetchTarget.projects);
    _warmOnce(target: AppPrefetchTarget.allProjects);
  }

  void warmSettings() {
    _warmOnce(target: AppPrefetchTarget.currentUserSettings);
    _warmOnce(target: AppPrefetchTarget.currentSubscription);
  }

  void warmProjectReport(String projectId) {
    _warmOnce(target: AppPrefetchTarget.reportMetrics, projectId: projectId);
  }
}

final appPrefetcherProvider = Provider<AppPrefetcher>((ref) {
  Future<void> start(Future<dynamic> future) async {
    try {
      await future;
    } catch (_) {}
  }

  return AppPrefetcher(
    warm: ({required target, projectId}) {
      switch (target) {
        case AppPrefetchTarget.dashboardSummary:
          final workspaceId = ref.read(activeWorkspaceIdProvider);
          if (workspaceId != null && workspaceId.isNotEmpty) {
            return start(
              ref.read(dashboardSummaryProvider(workspaceId).future),
            );
          }
          break;
        case AppPrefetchTarget.currentSubscription:
          return start(ref.read(currentSubscriptionStreamProvider.future));
        case AppPrefetchTarget.currentUsage:
          return start(ref.read(currentUsageProvider.future));
        case AppPrefetchTarget.currentUserSettings:
          return start(ref.read(currentUserSettingsProvider.future));
        case AppPrefetchTarget.projects:
          return start(ref.read(projectsProvider.future));
        case AppPrefetchTarget.allProjects:
          return start(ref.read(allProjectsProvider.future));
        case AppPrefetchTarget.workers:
          return start(ref.read(workersProvider.future));
        case AppPrefetchTarget.reportMetrics:
          if (projectId != null && projectId.isNotEmpty) {
            ref.read(reportProjectIdProvider.notifier).state = projectId;
            return Future.wait([
              start(ref.read(reportBaseMetricsProvider.future)),
              start(ref.read(reportPendingActionsProvider.future)),
            ]);
          }
          break;
      }
    },
  );
});
