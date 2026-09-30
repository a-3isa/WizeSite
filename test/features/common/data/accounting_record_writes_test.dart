import 'dart:io';

import 'package:buildtrack_app/core/services/app_telemetry.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/common/presentation/controllers/domain_accounting_record_draft.dart';
import 'package:buildtrack_app/features/common/presentation/controllers/domain_accounting_save_adapter.dart';
import 'package:buildtrack_app/features/contractors/data/contractor_accounting_repository.dart';
import 'package:buildtrack_app/features/contractors/domain/contractor_accounting_record.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/local_db.dart';

class _MockCallableClient extends Mock implements CallableClient {}

class _MockTelemetry extends Mock implements AppTelemetry {}

/// Accounting-record saves in self-hosted builds (spec 004, T082): queued as
/// JSON, replayed to the family's upsert RPC with the action id as the key,
/// and never written to Firestore.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;
  late _MockCallableClient client;
  late WorkspaceMutationService mutations;
  late FakeFirebaseFirestore firestore;
  late LocalTestDb local;
  final calls = <({String name, String? key, Map<String, dynamic> payload})>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('accounting_writes_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('accounting_writes_test');
    queue = OfflineActionQueue(box);
    client = _MockCallableClient();
    final telemetry = _MockTelemetry();
    when(() => telemetry.log(any(), any())).thenAnswer((_) async {});
    calls.clear();
    when(
      () => client.call<void>(
        functionName: any(named: 'functionName'),
        payload: any(named: 'payload'),
        parseResult: any(named: 'parseResult'),
        defaultErrorMessage: any(named: 'defaultErrorMessage'),
        httpFunctionName: any(named: 'httpFunctionName'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((invocation) async {
      calls.add((
        name: invocation.namedArguments[#functionName] as String,
        key: invocation.namedArguments[#idempotencyKey] as String?,
        payload: Map<String, dynamic>.from(
          invocation.namedArguments[#payload] as Map,
        ),
      ));
    });
    mutations = WorkspaceMutationService(client, queue, telemetry);
    firestore = FakeFirebaseFirestore();
    local = await LocalTestDb.open();
  });

  tearDown(() async {
    await local.dispose();
    await box.close();
    await Hive.deleteBoxFromDisk('accounting_writes_test');
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> drain() async {
    for (final action in await queue.list()) {
      await mutations.processQueuedAction(action);
    }
  }

  test(
    'repository save queues the record and replays it to the upsert RPC',
    () async {
      final repo = LocalContractorAccountingRepository(
        firestore,
        Future.value(local.db),
        mutations: mutations,
      );
      await repo.save(
        ContractorAccountingRecord(
          id: 'c1',
          workspaceId: 'ws_1',
          projectId: 'p1',
          contractorId: 'k1',
          contractorName: 'مقاول',
          description: 'دفعة',
          amount: 500,
          date: DateTime.utc(2026, 6, 1),
          paymentMethod: 'cash',
          paymentStatus: 'paid',
          notes: '',
          attachments: const [],
        ),
      );
      final queued = await queue.list();
      expect(queued.single.type, OfflineActionTypes.upsertAccountingRecord);
      await drain();
      final call = calls.singleWhere(
        (c) => c.name == 'upsertContractorAccountingRecord',
      );
      expect(call.key, queued.single.id);
      expect(call.payload['id'], 'c1');
      expect(call.payload['date'], '2026-06-01T00:00:00.000Z');
      expect(call.payload['contractorName'], 'مقاول');
      final firestoreDocs = await firestore
          .collection('contractor_accounting_records')
          .get();
      expect(firestoreDocs.docs, isEmpty);
    },
  );

  test(
    'the domain save adapter queues equipment records with providerId',
    () async {
      final adapter = DomainAccountingSaveAdapter(
        firestore,
        mutations: mutations,
      );
      await adapter.save(
        collectionName: 'equipment_accounting_records',
        draft: DomainAccountingRecordDraft(
          workspaceId: 'ws_1',
          projectId: 'p1',
          ownerIdField: 'providerId',
          ownerNameField: 'providerName',
          ownerId: 'eq1',
          ownerName: 'حفار',
          description: 'إيجار',
          amount: 900,
          date: DateTime.utc(2026, 6, 2),
          paymentMethod: 'cash',
          paymentStatus: 'unpaid',
          notes: '',
        ),
      );
      await drain();
      final call = calls.singleWhere(
        (c) => c.name == 'upsertEquipmentAccountingRecord',
      );
      expect(call.payload['providerId'], 'eq1');
      expect(call.payload['id'], isNotEmpty);
      expect(call.payload['date'], '2026-06-02T00:00:00.000Z');
    },
  );
}
