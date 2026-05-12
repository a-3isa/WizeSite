import 'package:buildtrack_app/core/constants/app_limits.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
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
    this._firestore,
    this._functions, {
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final DateTime Function() _nowProvider;

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
    DocumentSnapshot<Map<String, dynamic>>? counterDoc;
    try {
      counterDoc = await _firestore
          .collection('usage_counters')
          .doc(counterId)
          .get();
    } catch (_) {}

    int activeProjects = 0;
    try {
      final snap = await _firestore
          .collection('projects')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('status', isEqualTo: 'active')
          .where('isArchived', isEqualTo: false)
          .count()
          .get();
      activeProjects = snap.count ?? 0;
    } catch (_) {}

    int memberCount = 1;
    try {
      final snap = await _firestore
          .collection('memberships')
          .where('workspaceId', isEqualTo: workspaceId)
          .count()
          .get();
      memberCount = snap.count ?? 1;
    } catch (_) {}

    final data = counterDoc?.data() ?? const <String, dynamic>{};

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
    final counterStream = _firestore
        .collection('usage_counters')
        .doc(counterId)
        .snapshots();
    final projectsStream = _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('status', isEqualTo: 'active')
        .where('isArchived', isEqualTo: false)
        .snapshots();
    final membershipsStream = _firestore
        .collection('memberships')
        .where('workspaceId', isEqualTo: workspaceId)
        .snapshots();

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
  return FirebaseUsageQuotaRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
  );
});
