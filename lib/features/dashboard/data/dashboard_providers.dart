import 'dart:async';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dashboardSummaryProvider =
    StreamProvider.family<Map<String, num>, String>((ref, workspaceId) async* {
      final firestore = ref.watch(firestoreProvider);

      final streams = [
        firestore
            .collection('projects')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('isArchived', isEqualTo: false)
            .snapshots(),
        firestore
            .collection('expenses')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('isArchived', isEqualTo: false)
            .snapshots(),
        firestore
            .collection('payments')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('isArchived', isEqualTo: false)
            .snapshots(),
        firestore
            .collection('worker_entries')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('isArchived', isEqualTo: false)
            .snapshots(),
      ];

      final controller = StreamController<void>.broadcast();
      final subs =
          streams.map((s) => s.listen((_) => controller.add(null))).toList();

      // Helper to calculate summary from fresh data
      Future<Map<String, num>> calculate() async {
        final projectsCount = await firestore
            .collection('projects')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('isArchived', isEqualTo: false)
            .count()
            .get();
        final activeProjectsCount = await firestore
            .collection('projects')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('status', isEqualTo: 'active')
            .where('isArchived', isEqualTo: false)
            .count()
            .get();

        final expensesSnap = await firestore
            .collection('expenses')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('isArchived', isEqualTo: false)
            .limit(500)
            .get();
        final paymentsSnap = await firestore
            .collection('payments')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('isArchived', isEqualTo: false)
            .limit(500)
            .get();
        final workerEntriesSnap = await firestore
            .collection('worker_entries')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('isArchived', isEqualTo: false)
            .limit(500)
            .get();

        final expenses = expensesSnap.docs.fold<num>(
          0,
          (total, doc) => total + ((doc.data()['amount'] as num?) ?? 0),
        );
        final labor = workerEntriesSnap.docs.fold<num>(
          0,
          (total, doc) => total + ((doc.data()['totalCost'] as num?) ?? 0),
        );
        final income = paymentsSnap.docs.fold<num>(
          0,
          (total, doc) => total + ((doc.data()['amount'] as num?) ?? 0),
        );

        final totalExpenses = expenses + labor;
        return {
          'totalProjects': projectsCount.count ?? 0,
          'activeProjects': activeProjectsCount.count ?? 0,
          'totalExpenses': totalExpenses,
          'totalIncome': income,
          'net': income - totalExpenses,
        };
      }

      yield await calculate();

      try {
        await for (final _ in controller.stream) {
          yield await calculate();
        }
      } finally {
        for (final s in subs) {
          await s.cancel();
        }
        await controller.close();
      }
    });
