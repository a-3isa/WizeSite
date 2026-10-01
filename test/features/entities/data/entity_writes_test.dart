import 'dart:io';

import 'package:buildtrack_app/core/services/app_telemetry.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/local_db.dart';

class _MockCallableClient extends Mock implements CallableClient {}

class _MockTelemetry extends Mock implements AppTelemetry {}

/// Contact writes in self-hosted builds (spec 004, T082): queued for the
/// contact RPCs, returned at once, never written to Firestore.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;
  late LocalTestDb local;
  late LocalEntityRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('entity_writes_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('entity_writes_test');
    queue = OfflineActionQueue(box);
    final client = _MockCallableClient();
    final telemetry = _MockTelemetry();
    when(() => telemetry.log(any(), any())).thenAnswer((_) async {});
    when(
      () => client.call<void>(
        functionName: any(named: 'functionName'),
        payload: any(named: 'payload'),
        parseResult: any(named: 'parseResult'),
        defaultErrorMessage: any(named: 'defaultErrorMessage'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async {});
    local = await LocalTestDb.open();
    await local.seedRows('entities', [
      {
        'id': 'ent1',
        'workspace_id': 'ws_1',
        'type': 'supplier',
        'name': 'Ahmed',
        'normalized_name': 'ahmed',
        'phone_number': '010',
        'notes': '',
        'attachments':
            '[{"id":"a1","fileName":"r.jpg","storagePath":"attachments/u1/r.jpg","contentType":"image/jpeg","uploadedAt":"2026-05-01T00:00:00.000Z"}]',
        'last_used_at': '2026-05-01 00:00:00Z',
        'created_at': '2026-04-01 00:00:00Z',
      },
    ]);
    repo = LocalEntityRepository(
      Future.value(local.db),
      WorkspaceMutationService(client, queue, telemetry),
    );
  });

  tearDown(() async {
    await local.dispose();
    await box.close();
    await Hive.deleteBoxFromDisk('entity_writes_test');
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<List<OfflineAction>> queued() => queue.list();

  test(
    'createEntity queues an upsert with a client id and returns it',
    () async {
      final created = await repo.createEntity(
        workspaceId: 'ws_1',
        name: '  Sara   Ali ',
        type: 'contractor',
        phoneNumber: '011',
        defaultRate: 12.5,
      );
      expect(created.normalizedName, 'sara ali');
      final action = (await queued()).single;
      expect(action.type, OfflineActionTypes.upsertEntity);
      expect(action.payload['id'], created.id);
      expect(action.payload['name'], 'Sara   Ali');
      expect(action.payload['phoneNumber'], '011');
      expect(action.payload['defaultRate'], 12.5);
    },
  );

  test(
    'updateEntity keeps workspace and attachments; clears dropped fields',
    () async {
      final updated = await repo.updateEntity(
        entityId: 'ent1',
        name: 'Ahmed Ali',
        type: 'supplier',
        notes: 'ملاحظة',
      );
      expect(updated.phoneNumber, '');
      final payload = (await queued()).single.payload;
      expect(payload['workspaceId'], 'ws_1');
      expect(payload['notes'], 'ملاحظة');
      expect(payload.containsKey('phoneNumber'), isFalse);
      expect((payload['attachments'] as List).single['id'], 'a1');
    },
  );

  test(
    'ensureEntity touches an existing contact instead of duplicating it',
    () async {
      final ensured = await repo.ensureEntity(
        workspaceId: 'ws_1',
        name: 'ahmed',
        type: 'supplier',
      );
      expect(ensured?.id, 'ent1');
      final action = (await queued()).single;
      expect(action.type, OfflineActionTypes.touchEntityLastUsed);
      expect(action.payload['workspaceId'], 'ws_1');
      expect(action.payload['entityId'], 'ent1');
    },
  );

  test('deleteEntity and saveAttachments carry the workspace', () async {
    await repo.deleteEntity('ent1');
    await repo.saveAttachments(entityId: 'ent1', attachments: const []);
    final actions = await queued();
    expect(actions.map((a) => a.type), [
      OfflineActionTypes.deleteEntity,
      OfflineActionTypes.upsertEntity,
    ]);
    expect(actions.first.payload['workspaceId'], 'ws_1');
    expect(actions.last.payload['attachments'], isEmpty);
    expect(actions.last.payload['name'], 'Ahmed');
  });
}
