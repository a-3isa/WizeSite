import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/projects/data/project_metrics_merger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dashboardSummaryProvider =
    StreamProvider.family<Map<String, num>, String>((ref, workspaceId) {
      final firestore = ref.watch(firestoreProvider);
      final queue = ref.watch(offlineActionQueueProvider);
      return _projectsSummaryStream(
        firestore: firestore,
        queue: queue,
        workspaceId: workspaceId,
      );
    });

Stream<Map<String, num>> _projectsSummaryStream({
  required FirebaseFirestore firestore,
  required OfflineActionQueue queue,
  required String workspaceId,
}) {
  final projectsStream = firestore
      .collection('projects')
      .where('workspaceId', isEqualTo: workspaceId)
      .where('isArchived', isEqualTo: false)
      .snapshots();
  final metricsStream = firestore
      .collection('project_metrics')
      .where('workspaceId', isEqualTo: workspaceId)
      .snapshots();

  final queueStream = queue.watch();

  return Stream.multi((controller) {
    QuerySnapshot<Map<String, dynamic>>? latestProjects;
    QuerySnapshot<Map<String, dynamic>>? latestMetrics;
    List<OfflineAction> latestActions = const [];

    void emit() {
      final projects = latestProjects?.docs ?? const [];
      final metricsByProjectId = {
        for (final doc in latestMetrics?.docs ?? const []) doc.id: doc.data(),
      };
      num totalExpenses = 0;
      num totalIncome = 0;
      num totalNet = 0;
      var activeProjects = 0;

      for (final doc in projects) {
        final data = mergeProjectMetricsData(
          projectData: doc.data(),
          metricsData: metricsByProjectId[doc.id],
        );
        final expenses = (data['totalExpenses'] as num?) ?? 0;
        final income =
            (data['totalPayments'] as num?) ??
            (data['totalIncome'] as num?) ??
            0;
        final net =
            (data['netProfit'] as num?) ??
            (data['net'] as num?) ??
            income - expenses;
        totalExpenses += expenses;
        totalIncome += income;
        totalNet += net;
        if ('${data['status'] ?? 'active'}' == 'active') {
          activeProjects += 1;
        }
      }

      final pending = _workspacePendingDelta(
        actions: latestActions,
        workspaceId: workspaceId,
      );

      controller.add(<String, num>{
        'totalProjects': projects.length + pending.pendingProjects,
        'activeProjects': activeProjects + pending.pendingProjects,
        'totalExpenses': totalExpenses + pending.pendingExpenses,
        'totalIncome': totalIncome + pending.pendingIncome,
        'net': totalNet + pending.pendingIncome - pending.pendingExpenses,
      });
    }

    final projectSub = projectsStream.listen((snapshot) {
      latestProjects = snapshot;
      emit();
    }, onError: controller.addError);
    final metricsSub = metricsStream.listen((snapshot) {
      latestMetrics = snapshot;
      emit();
    }, onError: controller.addError);
    final queueSub = queueStream.listen((actions) {
      latestActions = actions;
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await projectSub.cancel();
      await metricsSub.cancel();
      await queueSub.cancel();
    };
  });
}

({int pendingProjects, num pendingExpenses, num pendingIncome})
_workspacePendingDelta({
  required List<OfflineAction> actions,
  required String workspaceId,
}) {
  var pendingProjects = 0;
  num pendingExpenses = 0;
  num pendingIncome = 0;

  for (final action in actions) {
    final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
    if (payloadWorkspaceId != workspaceId) {
      continue;
    }
    switch (action.type) {
      case OfflineActionTypes.createProject:
        pendingProjects += 1;
        break;
      case OfflineActionTypes.createExpense:
        pendingExpenses += (action.payload['amount'] as num?) ?? 0;
        break;
      case OfflineActionTypes.updateExpense:
        pendingExpenses -= (action.payload['previousAmount'] as num?) ?? 0;
        pendingExpenses += (action.payload['amount'] as num?) ?? 0;
        break;
      case OfflineActionTypes.createWorkerEntry:
        final daysWorked = (action.payload['daysWorked'] as num?) ?? 0;
        final dailyWage = (action.payload['dailyWage'] as num?) ?? 0;
        pendingExpenses += daysWorked * dailyWage;
        break;
      case OfflineActionTypes.updateWorkerEntry:
        pendingExpenses -=
            (action.payload['previousTotalCost'] as num?) ??
            (((action.payload['previousDaysWorked'] as num?) ?? 0) *
                ((action.payload['previousDailyWage'] as num?) ?? 0));
        pendingExpenses +=
            (action.payload['totalCost'] as num?) ??
            (((action.payload['daysWorked'] as num?) ?? 0) *
                ((action.payload['dailyWage'] as num?) ?? 0));
        break;
      case OfflineActionTypes.createPayment:
        pendingIncome += (action.payload['amount'] as num?) ?? 0;
        break;
      case OfflineActionTypes.updatePayment:
        pendingIncome -= (action.payload['previousAmount'] as num?) ?? 0;
        pendingIncome += (action.payload['amount'] as num?) ?? 0;
        break;
      default:
        break;
    }
  }

  return (
    pendingProjects: pendingProjects,
    pendingExpenses: pendingExpenses,
    pendingIncome: pendingIncome,
  );
}
