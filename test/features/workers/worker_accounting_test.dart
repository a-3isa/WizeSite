import 'package:buildtrack_app/features/workers/data/worker_accounting_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_accounting_record.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('worker accounting records persist attachments and list by worker', () async {
    final firestore = FakeFirebaseFirestore();
    final repository = WorkerAccountingRepository(firestore);
    final record = WorkerAccountingRecord(
      id: 'record_1',
      workspaceId: 'workspace_1',
      projectId: 'project_1',
      workerId: 'worker_1',
      workerName: 'Worker One',
      description: 'Weekly labor settlement',
      amount: 250,
      date: DateTime.utc(2026, 5, 20),
      paymentMethod: 'cash',
      paymentStatus: 'paid',
      attachments: const [],
    );

    await repository.save(record);

    final records = await repository.fetchForWorker(
      workspaceId: 'workspace_1',
      workerId: 'worker_1',
    );
    expect(records, hasLength(1));
    expect(records.single.workerName, 'Worker One');
    expect(records.single.amount, 250);
  });
}
