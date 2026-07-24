import 'dart:io';

import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

Future<T> _readStreamProvider<T>(
  ProviderContainer container,
  StreamProvider<T> provider,
) {
  final subscription = container.listen(
    provider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  return container.read(provider.future);
}

/// Like [_readStreamProvider], but for providers whose `Stream.multi` merges
/// two independently-listened sources (e.g. a base Firestore query + the
/// offline queue) without gating the first emission on both having reported
/// in. Reading `.future` immediately can otherwise race and capture a
/// transient, partially-merged value. Pumping the event queue first lets
/// both underlying listeners fire before we read the settled state.
Future<T> _readSettledStreamProvider<T>(
  ProviderContainer container,
  StreamProvider<T> provider,
) async {
  final subscription = container.listen(
    provider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  await pumpEventQueue();
  return container.read(provider).requireValue;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;
  late FakeFirebaseFirestore firestore;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'dashboard_providers_test_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('dashboard_providers_test');
    queue = OfflineActionQueue(box);
    firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        offlineActionQueueProvider.overrideWithValue(queue),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await box.close();
    await Hive.deleteBoxFromDisk('dashboard_providers_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('weekly summary excludes future-dated transactions', () async {
    final now = DateTime.now();
    await firestore.collection('expenses').doc('expense_this_week').set({
      'workspaceId': 'workspace_1',
      'isArchived': false,
      'amount': 100,
      'date': DateTime(now.year, now.month, now.day),
    });
    await firestore.collection('expenses').doc('expense_future').set({
      'workspaceId': 'workspace_1',
      'isArchived': false,
      'amount': 900,
      'date': DateTime(
        now.year,
        now.month,
        now.day,
      ).add(const Duration(days: 14)),
    });

    final summary = await _readStreamProvider(
      container,
      dashboardWeeklySummaryProvider('workspace_1'),
    );

    expect(summary['weeklyExpenses'], 100);
  });

  test(
    'weekly summary ignores synced pending actions already reflected',
    () async {
      final now = DateTime.now();
      final date = DateTime(now.year, now.month, now.day);
      await firestore.collection('expenses').doc('expense_synced').set({
        'workspaceId': 'workspace_1',
        'isArchived': false,
        'amount': 100,
        'date': date,
      });
      final action = await queue.enqueue(
        type: OfflineActionTypes.createExpense,
        payload: {
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'amount': 100,
          'date': date.toIso8601String(),
        },
      );
      await queue.save(
        action.copyWith(
          status: OfflineActionStatus.synced,
          syncedAt: DateTime.now(),
        ),
      );

      final summary = await _readStreamProvider(
        container,
        dashboardWeeklySummaryProvider('workspace_1'),
      );

      expect(summary['weeklyExpenses'], 100);
    },
  );

  test(
    'weekly insights normalizes empty names and raw category keys',
    () async {
      final now = DateTime.now();
      final date = DateTime(now.year, now.month, now.day);
      await firestore.collection('expenses').doc('expense_1').set({
        'workspaceId': 'workspace_1',
        'isArchived': false,
        'amount': 100,
        'category': 'labor',
        'entityName': '',
        'paymentMethod': 'cash',
        'date': date,
      });

      final insights = await _readStreamProvider(
        container,
        dashboardWeeklyInsightsProvider('workspace_1'),
      );

      expect(insights.topEntity, 'unassigned');
      expect(insights.topCategory, 'labor');
      expect(insights.paymentSummary.keys, contains('cash'));
      expect(insights.recentTransactions.single.title, 'unassigned');
    },
  );

  test('dashboard snapshot parses one bounded maintained metrics document', () {
    final snapshot = DashboardSnapshot.fromMap({
      'totalProjects': 8,
      'activeProjects': 5,
      'totalExpenses': 1200,
      'totalIncome': 1800,
      'weeklyExpenses': 200,
      'weeklyIncome': 450,
      'topCategory': 'materials',
      'topEntity': 'Acme',
      'recentTransactions': [
        {
          'id': 'expense_1',
          'type': 'expense',
          'title': 'Steel',
          'amount': 90,
          'date': DateTime(2026, 6, 15).toIso8601String(),
        },
      ],
    });

    expect(snapshot.net, 600);
    expect(snapshot.weeklyNet, 250);
    expect(snapshot.recentTransactions, hasLength(1));
    expect(snapshot.recentTransactions.single.id, 'expense_1');
  });

  test(
    'member receives a restricted snapshot without financial totals',
    () async {
      final deniedContainer = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          offlineActionQueueProvider.overrideWithValue(queue),
          currentAccountingRoleProvider.overrideWithValue(
            const AsyncData(AccountingAccessRoleType.member),
          ),
        ],
      );
      addTearDown(deniedContainer.dispose);

      final snapshot = await _readStreamProvider(
        deniedContainer,
        dashboardSnapshotProvider('workspace_1'),
      );

      expect(snapshot.hasFinancialAccess, isFalse);
      expect(snapshot.totalExpenses, 0);
    },
  );

  test('accounting role reads the maintained workspace snapshot', () async {
    await firestore.collection('workspace_metrics').doc('workspace_1').set({
      'workspaceId': 'workspace_1',
      'totalProjects': 3,
      'activeProjects': 2,
      'totalExpenses': 400,
      'totalIncome': 700,
      'weeklyExpenses': 50,
      'weeklyIncome': 90,
    });
    final allowedContainer = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        offlineActionQueueProvider.overrideWithValue(queue),
        currentAccountingRoleProvider.overrideWithValue(
          const AsyncData(AccountingAccessRoleType.accountingApproved),
        ),
      ],
    );
    addTearDown(allowedContainer.dispose);

    final snapshot = await _readStreamProvider(
      allowedContainer,
      dashboardSnapshotProvider('workspace_1'),
    );

    expect(snapshot.hasFinancialAccess, isTrue);
    expect(snapshot.net, 300);
    expect(snapshot.weeklyNet, 40);
  });

  test(
    'worker attendance excludes a pending update that moves an in-window '
    'entry out of the window',
    () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final movedOutDate = today.subtract(const Duration(days: 40));

      // Base doc still reflects the OLD (in-window) date/daysWorked because
      // Firestore hasn't synced the pending edit yet.
      await firestore.collection('worker_entries').doc('entry_1').set({
        'workspaceId': 'workspace_1',
        'isArchived': false,
        'workerId': 'worker_1',
        'projectId': 'project_1',
        'daysWorked': 3,
        'date': today,
      });

      await queue.enqueue(
        type: OfflineActionTypes.updateWorkerEntry,
        payload: {
          'workspaceId': 'workspace_1',
          'entryId': 'entry_1',
          'projectId': 'project_1',
          'daysWorked': 3,
          'dailyWage': 100,
          'date': movedOutDate.toIso8601String(),
          'previousProjectId': 'project_1',
          'previousDaysWorked': 3,
          'previousDailyWage': 100,
          'previousDate': today.toIso8601String(),
        },
      );

      final summary = await _readSettledStreamProvider(
        container,
        dashboardWorkerAttendanceProvider('workspace_1'),
      );

      expect(summary.workerCount, 0);
      expect(summary.manDays, 0);
    },
  );

  test(
    'worker attendance keeps counting a worker whose other entry stays '
    'in-window after a sibling entry is pending-moved out',
    () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final movedOutDate = today.subtract(const Duration(days: 40));

      await firestore.collection('worker_entries').doc('entry_1').set({
        'workspaceId': 'workspace_1',
        'isArchived': false,
        'workerId': 'worker_1',
        'projectId': 'project_1',
        'daysWorked': 3,
        'date': today,
      });
      await firestore.collection('worker_entries').doc('entry_2').set({
        'workspaceId': 'workspace_1',
        'isArchived': false,
        'workerId': 'worker_1',
        'projectId': 'project_1',
        'daysWorked': 2,
        'date': today,
      });

      await queue.enqueue(
        type: OfflineActionTypes.updateWorkerEntry,
        payload: {
          'workspaceId': 'workspace_1',
          'entryId': 'entry_1',
          'projectId': 'project_1',
          'daysWorked': 3,
          'dailyWage': 100,
          'date': movedOutDate.toIso8601String(),
          'previousProjectId': 'project_1',
          'previousDaysWorked': 3,
          'previousDailyWage': 100,
          'previousDate': today.toIso8601String(),
        },
      );

      final summary = await _readSettledStreamProvider(
        container,
        dashboardWorkerAttendanceProvider('workspace_1'),
      );

      // worker_1 is NOT blindly dropped from the distinct count just
      // because entry_1 moved out of window — entry_2 still keeps them in.
      expect(summary.workerCount, 1);
      expect(summary.manDays, 2);
    },
  );

  test(
    'worker attendance adds the full day count (not a stale delta) when a '
    'pending update moves an entry into the window',
    () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final movedFromDate = today.subtract(const Duration(days: 40));

      // No base doc: the entry's currently-stored (unsynced) date is still
      // outside the window, so the base query correctly excludes it — the
      // pending action is the only source of this contribution.
      await queue.enqueue(
        type: OfflineActionTypes.updateWorkerEntry,
        payload: {
          'workspaceId': 'workspace_1',
          'entryId': 'entry_3',
          'projectId': 'project_1',
          'daysWorked': 4,
          'dailyWage': 100,
          'date': today.toIso8601String(),
          'previousProjectId': 'project_1',
          'previousDaysWorked': 4,
          'previousDailyWage': 100,
          'previousDate': movedFromDate.toIso8601String(),
        },
      );

      final summary = await _readSettledStreamProvider(
        container,
        dashboardWorkerAttendanceProvider('workspace_1'),
      );

      expect(summary.manDays, 4);
    },
  );
}
