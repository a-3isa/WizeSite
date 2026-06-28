import 'dart:io';

import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;
  late FakeFirebaseFirestore firestore;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'entity_aggregation_providers_test_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('entity_aggregation_providers_test');
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
    await Hive.deleteBoxFromDisk('entity_aggregation_providers_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'reads maintained entity summaries instead of raw transactions',
    () async {
      await firestore.collection('entity_summaries').doc('summary_1').set({
        'workspaceId': 'workspace_1',
        'entityId': 'entity_1',
        'entityName': 'Steel Supplier',
        'entityType': 'supplier',
        'totalExpenses': 100,
        'totalPayments': 40,
        'transactionCount': 2,
        'attachmentCount': 1,
        'latestTransactionDate': DateTime.utc(2026, 5, 28),
        'updatedAt': DateTime.utc(2026, 5, 28),
      });
      await firestore.collection('expenses').doc('raw_expense').set({
        'workspaceId': 'workspace_1',
        'entityId': 'entity_raw',
        'entityName': 'Raw Historical Scan',
        'entityType': 'supplier',
        'amount': 999,
        'isArchived': false,
        'date': DateTime.utc(2026, 5, 28),
      });

      final summaries = await _readStreamProvider(
        container,
        entityAggregationsProvider('workspace_1'),
      );

      expect(summaries, hasLength(1));
      expect(summaries.single.entityName, 'Steel Supplier');
      expect(summaries.single.totalExpenses, 100);
    },
  );

  test('merges unsynced entity create actions into summaries', () async {
    await queue.enqueue(
      type: OfflineActionTypes.createExpense,
      payload: {
        'workspaceId': 'workspace_1',
        'entityId': 'entity_pending',
        'entityName': 'Pending Supplier',
        'entityType': 'supplier',
        'amount': 75,
        'date': DateTime.utc(2026, 5, 28).toIso8601String(),
        'attachments': [
          {'id': 'attachment_1'},
        ],
      },
    );

    final summaries = await _readStreamProvider(
      container,
      entityAggregationsProvider('workspace_1'),
    );

    expect(summaries, hasLength(1));
    expect(summaries.single.entityName, 'Pending Supplier');
    expect(summaries.single.totalExpenses, 75);
    expect(summaries.single.attachmentCount, 1);
  });

  test(
    'merges domain accounting records into entity totals and breakdowns',
    () async {
      await firestore
          .collection('worker_accounting_records')
          .doc('worker_1')
          .set({
            'workspaceId': 'workspace_1',
            'projectId': 'project_1',
            'workerId': 'worker_1',
            'workerName': 'Worker One',
            'amount': 120,
            'date': DateTime.utc(2026, 5, 28),
            'paymentMethod': 'cash',
            'attachments': [
              {'id': 'attachment_1'},
            ],
          });
      await firestore
          .collection('equipment_accounting_records')
          .doc('equipment_1')
          .set({
            'workspaceId': 'workspace_1',
            'projectId': 'project_1',
            'providerId': 'equipment_1',
            'providerName': 'Crane Rental',
            'amount': 300,
            'date': DateTime.utc(2026, 5, 27),
            'paymentMethod': 'bank',
          });

      final summaries = await _readStreamProvider(
        container,
        entityAggregationsProvider('workspace_1'),
      );

      final worker = summaries.singleWhere(
        (summary) => summary.entityId == 'worker_1',
      );
      final equipment = summaries.singleWhere(
        (summary) => summary.entityId == 'equipment_1',
      );
      expect(worker.entityType, 'worker');
      expect(worker.totalExpenses, 120);
      expect(worker.categoryBreakdown, {'labor': 120});
      expect(worker.paymentMethodBreakdown, {'cash': 120});
      expect(worker.attachmentCount, 1);
      expect(equipment.entityType, 'equipment');
      expect(equipment.categoryBreakdown, {'equipment': 300});
    },
  );
}
