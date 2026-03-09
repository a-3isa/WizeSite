import 'package:buildtrack_app/core/constants/app_limits.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_quota_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class FirebaseUsageQuotaRepository implements UsageQuotaRepository {
  FirebaseUsageQuotaRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Future<UsageSnapshot> getUsageSnapshot({
    required String workspaceId,
    required PlanLimits limits,
  }) async {
    final key = _periodKey();
    final counterId = '${workspaceId}_$key';
    final counterDoc = await _firestore
        .collection('usage_counters')
        .doc(counterId)
        .get();
    final activeProjectsSnap = await _firestore
        .collection('projects')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('status', isEqualTo: 'active')
        .where('isArchived', isEqualTo: false)
        .count()
        .get();
    final membersSnap = await _firestore
        .collection('memberships')
        .where('workspaceId', isEqualTo: workspaceId)
        .count()
        .get();

    final data = counterDoc.data() ?? const <String, dynamic>{};

    return UsageSnapshot(
      periodKey: key,
      activeProjects: activeProjectsSnap.count ?? 0,
      expensesCount: (data['expensesCount'] as num?)?.toInt() ?? 0,
      paymentsCount: (data['paymentsCount'] as num?)?.toInt() ?? 0,
      workerEntriesCount: (data['workerEntriesCount'] as num?)?.toInt() ?? 0,
      memberCount: membersSnap.count ?? 1,
      limits: limits,
    );
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

  String _periodKey() => DateFormat('yyyyMM').format(DateTime.now());
}

final usageQuotaRepositoryProvider = Provider<UsageQuotaRepository>((ref) {
  return FirebaseUsageQuotaRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
  );
});
