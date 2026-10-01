import 'package:buildtrack_app/features/workers/data/worker_accounting_repository.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/local_db.dart';

class _MockMutations extends Mock implements WorkspaceMutationService {}

void main() {
  late LocalTestDb local;
  late WorkerAccountingRepository repository;

  setUp(() async {
    local = await LocalTestDb.open();
    repository = WorkerAccountingRepository(
      Future.value(local.db),
      _MockMutations(),
    );
    await local.seedRows('worker_accounting_records', [
      {
        'id': 'r1',
        'workspace_id': 'ws_1',
        'worker_id': 'w1',
        'worker_name': 'علي',
        'amount': 250.0,
        'paid_amount': 100.0,
        'payment_status': 'partial',
        'date': '2026-06-01 00:00:00Z',
        'attachments': '[]',
      },
      {
        'id': 'r2',
        'workspace_id': 'ws_1',
        'worker_id': 'w1',
        'amount': 50.0,
        'date': '2026-06-09 00:00:00Z',
        'attachments': '[]',
      },
      {
        'id': 'r_other',
        'workspace_id': 'ws_1',
        'worker_id': 'w2',
        'amount': 1.0,
        'date': '2026-06-09 00:00:00Z',
        'attachments': '[]',
      },
    ]);
    await local.seedRows('worker_accounting_summaries', [
      {
        'id': 'ws_1_w1',
        'workspace_id': 'ws_1',
        'worker_id': 'w1',
        'payload':
            '{"workspaceId":"ws_1","workerId":"w1","totalAmount":300,"confirmedPaid":100,"confirmedOutstanding":200,"unresolvedLegacyCount":0}',
      },
    ]);
  });
  tearDown(() => local.dispose());

  test('fetchForWorker: newest first, worker scoped, dates parsed', () async {
    final records = await repository.fetchForWorker(
      workspaceId: 'ws_1',
      workerId: 'w1',
    );
    expect(records.map((r) => r.id), ['r2', 'r1']);
    expect(records.last.workerName, 'علي');
    expect(records.last.paidAmount, 100);
    expect(records.last.date, DateTime.utc(2026, 6, 1));
  });

  test(
    'fetchSummary reads the recomputed payload; missing summary is null',
    () async {
      final summary = await repository.fetchSummary(
        workspaceId: 'ws_1',
        workerId: 'w1',
      );
      expect(summary?.totalAmount, 300);
      expect(summary?.confirmedOutstanding, 200);
      expect(
        await repository.fetchSummary(workspaceId: 'ws_1', workerId: 'w2'),
        isNull,
      );
    },
  );
}
