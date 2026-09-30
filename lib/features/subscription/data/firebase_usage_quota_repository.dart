import 'package:buildtrack_app/core/constants/app_limits.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_quota_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:async';

String usagePeriodKey(DateTime now) => DateFormat('yyyyMM').format(now.toUtc());

class FirebaseUsageQuotaRepository implements UsageQuotaRepository {
  FirebaseUsageQuotaRepository(
    FirebaseFirestore firestore,
    this._functions, {
    DateTime Function()? nowProvider,
  }) : _source = FirestoreDocSource(firestore),
       _nowProvider = nowProvider ?? DateTime.now;

  /// Reads through [source] (local replica in self-hosted builds, spec 004).
  FirebaseUsageQuotaRepository.withSource(
    DocSource source,
    this._functions, {
    DateTime Function()? nowProvider,
  }) : _source = source,
       _nowProvider = nowProvider ?? DateTime.now;

  final DocSource _source;
  final FirebaseFunctions _functions;
  final DateTime Function() _nowProvider;

  static DocQuery _activeProjectsQuery(String workspaceId) => DocQuery(
    'projects',
    equals: {
      'workspaceId': workspaceId,
      'status': 'active',
      'isArchived': false,
    },
  );

  static DocQuery _membershipsQuery(String workspaceId) =>
      DocQuery('memberships', equals: {'workspaceId': workspaceId});

  @override
  Future<UsageSnapshot> getUsageSnapshot({
    required String workspaceId,
    required PlanLimits limits,
  }) async {
    final key = _periodKey();
    final counterId = '${workspaceId}_$key';

    // Each query is fetched independently so a single failure (e.g. an
    // aggregate count that doesn't work offline) doesn't blow up the whole
    // snapshot — it just falls back to 0 / last-cached values.
    Doc? counterDoc;
    try {
      counterDoc = await _source.getDoc('usage_counters', counterId);
    } catch (_) {}

    int activeProjects = 0;
    try {
      activeProjects = await _source.count(_activeProjectsQuery(workspaceId));
    } catch (_) {}

    int memberCount = 1;
    try {
      memberCount = await _source.count(_membershipsQuery(workspaceId));
    } catch (_) {}

    final data = counterDoc?.data ?? const <String, dynamic>{};

    return UsageSnapshot(
      periodKey: key,
      activeProjects: activeProjects,
      expensesCount: (data['expensesCount'] as num?)?.toInt() ?? 0,
      paymentsCount: (data['paymentsCount'] as num?)?.toInt() ?? 0,
      workerEntriesCount: (data['workerEntriesCount'] as num?)?.toInt() ?? 0,
      memberCount: memberCount,
      limits: limits,
    );
  }

  @override
  Stream<UsageSnapshot> watchUsageSnapshot({
    required String workspaceId,
    required PlanLimits limits,
  }) async* {
    final key = _periodKey();
    final counterId = '${workspaceId}_$key';

    // Initial fetch — fall back to empty snapshot if offline / no cache.
    try {
      yield await getUsageSnapshot(workspaceId: workspaceId, limits: limits);
    } catch (_) {
      yield UsageSnapshot.empty(limits: limits);
    }

    // Watch for changes in usage counters, projects, and memberships.
    final counterStream = _source.watchDoc('usage_counters', counterId);
    final projectsStream = _source.watch(_activeProjectsQuery(workspaceId));
    final membershipsStream = _source.watch(_membershipsQuery(workspaceId));

    final controller = StreamController<void>.broadcast();
    final subs = [
      counterStream.listen((_) => controller.add(null), onError: (_) {}),
      projectsStream.listen((_) => controller.add(null), onError: (_) {}),
      membershipsStream.listen((_) => controller.add(null), onError: (_) {}),
    ];

    try {
      await for (final _ in controller.stream) {
        try {
          yield await getUsageSnapshot(
            workspaceId: workspaceId,
            limits: limits,
          );
        } catch (_) {
          // Keep last emitted value on failed refresh.
        }
      }
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
      await controller.close();
    }
  }

  @override
  Future<LimitCheckResult> checkLimit({
    required String workspaceId,
    required LimitType type,
    required int delta,
  }) async {
    try {
      final callable = _functions.httpsCallable('checkLimit');
      final response = await callable.call<Map<String, dynamic>>({
        'workspaceId': workspaceId,
        'type': type.name,
        'delta': delta,
      });
      final data = response.data;
      return LimitCheckResult(
        allowed: data['allowed'] as bool? ?? false,
        limitType: type,
        current: (data['current'] as num?)?.toInt() ?? 0,
        max: (data['max'] as num?)?.toInt() ?? 0,
        resetAt: DateTime.tryParse(data['resetAt'] as String? ?? ''),
      );
    } catch (_) {
      // If callable check isn't deployed yet, fallback to conservative local free limits.
      final snapshot = await getUsageSnapshot(
        workspaceId: workspaceId,
        limits: PlanLimits.free(),
      );
      final current = snapshot.currentByType(type);
      final max = snapshot.maxByType(type);
      return LimitCheckResult(
        allowed: current + delta <= max,
        limitType: type,
        current: current,
        max: max == 0 ? AppLimits.proLimit : max,
      );
    }
  }

  String _periodKey() => usagePeriodKey(_nowProvider());
}

final usageQuotaRepositoryProvider = Provider<UsageQuotaRepository>((ref) {
  return FirebaseUsageQuotaRepository.withSource(
    ref.watch(docSourceProvider),
    ref.watch(functionsProvider),
  );
});
