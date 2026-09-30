import 'dart:async';

/// Dashboard and activity providers over the local replica (spec 004, T048):
/// the same provider code, fed by [LocalDocSource] instead of Firestore.
import 'dart:io';

import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/features/activity/data/activity_providers.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../../../helpers/local_db.dart';

Future<T> _first<T>(ProviderContainer container, StreamProvider<T> provider) {
  final sub = container.listen(provider.future, (_, _) {});
  addTearDown(sub.close);
  return sub.read();
}

Future<T> _until<T>(
  ProviderContainer container,
  StreamProvider<T> provider,
  bool Function(T value) ready,
) {
  final completer = Completer<T>();
  final sub = container.listen<AsyncValue<T>>(provider, (_, next) {
    final value = next.value;
    if (value != null && ready(value) && !completer.isCompleted) {
      completer.complete(value);
    }
  }, fireImmediately: true);
  addTearDown(sub.close);
  return completer.future.timeout(const Duration(seconds: 5));
}

void main() {
  late Directory tempDir;
  late Box<String> box;
  late LocalTestDb local;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dashboard_local_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('dashboard_local_test');
    local = await LocalTestDb.open();
    container = ProviderContainer(
      overrides: [
        docSourceProvider.overrideWithValue(
          LocalDocSource(Future.value(local.db)),
        ),
        offlineActionQueueProvider.overrideWithValue(OfflineActionQueue(box)),
        currentAccountingRoleProvider.overrideWithValue(
          const AsyncData(AccountingAccessRoleType.owner),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await local.dispose();
    await box.close();
    await Hive.deleteBoxFromDisk('dashboard_local_test');
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('dashboard snapshot reads the recomputed workspace metrics', () async {
    await local.seedRows('workspace_metrics', [
      {
        'id': 'ws_1',
        'payload':
            '{"totalProjects":2,"activeProjects":1,"totalExpenses":700,"totalIncome":1000,"weeklyExpenses":50,"weeklyIncome":90}',
      },
    ]);
    final snapshot = await _first(container, dashboardSnapshotProvider('ws_1'));
    expect(snapshot.hasFinancialAccess, isTrue);
    expect(snapshot.totalProjects, 2);
    expect(snapshot.net, 300);
    expect(snapshot.weeklyNet, 40);
  });

  test(
    'activity feed merges recent expenses and payments newest first',
    () async {
      await local.seedRows('expenses', [
        {
          'id': 'e1',
          'workspace_id': 'ws_1',
          'project_id': 'p1',
          'amount': 10.0,
          'date': '2026-06-01 00:00:00Z',
          'entity_name': 'مورد',
          'is_archived': 0,
          'attachments': '[]',
        },
        {
          'id': 'e_arch',
          'workspace_id': 'ws_1',
          'project_id': 'p1',
          'amount': 99.0,
          'date': '2026-06-09 00:00:00Z',
          'is_archived': 1,
          'attachments': '[]',
        },
      ]);
      await local.seedRows('payments', [
        {
          'id': 'pay1',
          'workspace_id': 'ws_1',
          'project_id': 'p1',
          'amount': 20.0,
          'date': '2026-06-05 00:00:00Z',
          'entity_name': 'عميل',
          'is_archived': 0,
          'attachments': '[]',
        },
      ]);
      // The provider emits as soon as either list arrives (same as on
      // Firestore); wait for the merged state.
      final items = await _until(
        container,
        workspaceActivityProvider('ws_1'),
        (value) => value.length == 2,
      );
      expect(items.map((i) => i.id), ['pay1', 'e1']);
      expect(items.last.title, 'مورد');
    },
  );
}
