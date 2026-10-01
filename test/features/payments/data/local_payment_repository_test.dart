import 'dart:io';

import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/local_db.dart';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

void main() {
  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;
  late LocalTestDb local;
  late LocalPaymentRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_payments_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('offline_actions_local_payments');
    queue = OfflineActionQueue(box);
    local = await LocalTestDb.open();
    repository = LocalPaymentRepository(
      _MockWorkspaceMutationService(),
      queue,
      Future.value(local.db),
    );
    Map<String, Object?> payment(
      String id,
      String date, {
      String project = 'p1',
      String method = 'cash',
      String status = 'paid',
      double? paid,
      int archived = 0,
    }) => {
      'id': id,
      'workspace_id': 'ws_1',
      'project_id': project,
      'amount': 100.0,
      'paid_amount': paid,
      'date': date,
      'payment_method': method,
      'payment_status': status,
      'is_archived': archived,
      'entity_name': 'عميل',
      'attachments': '[]',
    };
    await local.seedRows('payments', [
      payment('pay1', '2026-05-01 08:00:00Z'),
      payment(
        'pay2',
        '2026-05-20 08:00:00Z',
        method: 'bank',
        status: 'partial',
        paid: 40,
      ),
      payment('pay3', '2026-06-01 08:00:00Z', project: 'p2'),
      payment('pay_arch', '2026-06-02 08:00:00Z', archived: 1),
    ]);
  });

  tearDown(() async {
    await local.dispose();
    await box.close();
    await Hive.deleteBoxFromDisk('offline_actions_local_payments');
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('watchPayments: workspace-wide or per project, active only', () async {
    final all = await repository.watchPayments('ws_1').first;
    expect(all.map((p) => p.id), ['pay3', 'pay2', 'pay1']);
    final p1 = await repository.watchPayments('ws_1', projectId: 'p1').first;
    expect(p1.map((p) => p.id), ['pay2', 'pay1']);
    expect(p1.first.paidAmount, 40);
    expect(p1.first.paymentStatus, 'partial');
  });

  test('page filters by method and entity name; keyset paging', () async {
    final bank = await repository.fetchPaymentsPage(
      'ws_1',
      paymentMethod: 'bank',
    );
    expect(bank.items.map((p) => p.id), ['pay2']);
    final named = await repository.fetchPaymentsPage(
      'ws_1',
      entityName: 'عميل',
      pageSize: 2,
    );
    expect(named.items.map((p) => p.id), ['pay3', 'pay2']);
    final next = await repository.fetchPaymentsPage(
      'ws_1',
      entityName: 'عميل',
      pageSize: 2,
      cursor: named.nextCursor,
    );
    expect(next.items.map((p) => p.id), ['pay1']);
  });

  test('getPayment', () async {
    expect((await repository.getPayment('pay1'))?.amount, 100);
    expect(await repository.getPayment('missing'), isNull);
  });
}
