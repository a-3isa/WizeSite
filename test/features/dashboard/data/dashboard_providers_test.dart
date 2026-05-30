import 'dart:io';

import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

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

    final summary = await container.read(
      dashboardWeeklySummaryProvider('workspace_1').future,
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

      final summary = await container.read(
        dashboardWeeklySummaryProvider('workspace_1').future,
      );

      expect(summary['weeklyExpenses'], 100);
    },
  );
}
