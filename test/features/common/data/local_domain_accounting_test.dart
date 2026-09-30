import 'package:buildtrack_app/features/common/data/domain_accounting_records_source.dart';
import 'package:buildtrack_app/features/contractors/data/contractor_accounting_repository.dart';
import 'package:buildtrack_app/features/equipment/data/equipment_accounting_repository.dart';
import 'package:buildtrack_app/features/transport/data/transport_provider_accounting_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/local_db.dart';

void main() {
  late LocalTestDb local;

  Map<String, Object?> record(
    String id,
    String ownerColumn,
    String owner,
    String date, {
    double amount = 10,
  }) => {
    'id': id,
    'workspace_id': 'ws_1',
    ownerColumn: owner,
    'amount': amount,
    'date': date,
    'description': 'وصف $id',
    'attachments': '[]',
  };

  setUp(() async {
    local = await LocalTestDb.open();
    await local.seedRows('contractor_accounting_records', [
      record('c1', 'contractor_id', 'k1', '2026-06-01 00:00:00Z'),
      record('c2', 'contractor_id', 'k1', '2026-06-05 00:00:00Z', amount: 99),
      record('c3', 'contractor_id', 'k2', '2026-06-09 00:00:00Z'),
    ]);
    await local.seedRows('equipment_accounting_records', [
      record('e1', 'provider_id', 'p1', '2026-06-01 00:00:00Z'),
    ]);
    await local.seedRows('transport_provider_accounting_records', [
      record('t1', 'provider_id', 't1p', '2026-06-01 00:00:00Z'),
      record('t2', 'provider_id', 't1p', '2026-06-02 00:00:00Z'),
    ]);
  });
  tearDown(() => local.dispose());

  test(
    'contractor records: owner scoped, newest first, fields mapped',
    () async {
      final repo = LocalContractorAccountingRepository(
        FakeFirebaseFirestore(),
        Future.value(local.db),
      );
      final records = await repo.fetchForContractor(
        workspaceId: 'ws_1',
        contractorId: 'k1',
      );
      expect(records.map((r) => r.id), ['c2', 'c1']);
      expect(records.first.amount, 99);
      expect(records.first.description, 'وصف c2');
    },
  );

  test('equipment and transport provider records', () async {
    final equipment = LocalEquipmentAccountingRepository(
      FakeFirebaseFirestore(),
      Future.value(local.db),
    );
    expect(
      (await equipment.fetchForProvider(
        workspaceId: 'ws_1',
        providerId: 'p1',
      )).map((r) => r.id),
      ['e1'],
    );
    final transport = LocalTransportProviderAccountingRepository(
      FakeFirebaseFirestore(),
      Future.value(local.db),
    );
    expect(
      (await transport.fetchForProvider(
        workspaceId: 'ws_1',
        providerId: 't1p',
      )).map((r) => r.id),
      ['t2', 't1'],
    );
  });

  test('domain screen source: live list, owner scoped', () async {
    final records = await watchLocalDomainRecords(Future.value(local.db), (
      collection: 'contractor_accounting_records',
      ownerField: 'contractorId',
      ownerId: 'k1',
      workspaceId: 'ws_1',
    )).first;
    expect(records.map((r) => r.id), ['c2', 'c1']);
    expect(records.first.data['contractorId'], 'k1');
  });

  test('domain screen source rejects identifiers outside the allow-list', () {
    expect(
      () => watchLocalDomainRecords(Future.value(local.db), (
        collection: 'expenses; DROP TABLE x',
        ownerField: 'contractorId',
        ownerId: 'k1',
        workspaceId: 'ws_1',
      )),
      throwsArgumentError,
    );
  });
}
