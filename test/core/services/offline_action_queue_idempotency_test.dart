import 'dart:convert';
import 'dart:io';

import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/services/app_telemetry.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/self_hosted_rpc_transport.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockAppCheck extends Mock implements FirebaseAppCheck {}

class _MockTelemetry extends Mock implements AppTelemetry {}

/// A stand-in for the API's idempotency: one stored result per key; a new
/// key creates a record (spec 004, contracts/rpc-api.md "Idempotency").
class _FakeApi {
  final keys = <String>[];
  final results = <String, Map<String, dynamic>>{};
  int records = 0;

  /// Simulates a response lost on the way back: the server applied the call
  /// but the client sees a network failure and will replay it.
  bool dropNextResponse = false;

  Future<http.Response> handle(http.Request request) async {
    final key = request.headers['X-Idempotency-Key'] ?? '';
    keys.add(key);
    final result = results.putIfAbsent(key, () => {'id': 'rec_${++records}'});
    if (dropNextResponse) {
      dropNextResponse = false;
      throw const SocketException('connection reset');
    }
    return http.Response(
      jsonEncode({'result': result}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;
  late _FakeApi api;
  late WorkspaceMutationService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('queue_idempotency_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('queue_idempotency_test');
    queue = OfflineActionQueue(box);
    api = _FakeApi();
    final telemetry = _MockTelemetry();
    when(() => telemetry.log(any(), any())).thenAnswer((_) async {});
    final client = CallableClient(
      _MockFunctions(),
      _MockAuth(),
      _MockAppCheck(),
      telemetry,
      selfHostedTransport: SelfHostedRpcTransport(
        config: const BackendConfig(
          apiBaseUrl: 'https://api.example.com',
          syncUrl: 'https://sync.example.com',
        ),
        httpClient: MockClient(api.handle),
        idToken: ({required bool forceRefresh}) async => 'id-token',
        appCheckToken: () async => 'app-check',
      ),
    );
    service = WorkspaceMutationService(client, queue, telemetry);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('queue_idempotency_test');
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<OfflineAction> expenseAction() => queue.enqueue(
    type: OfflineActionTypes.createExpense,
    payload: {
      'workspaceId': 'ws_1',
      'projectId': 'p1',
      'category': 'materials',
      'amount': 100,
      'date': DateTime.utc(2026, 6, 1).toIso8601String(),
    },
  );

  test(
    'a queued action is sent with its own id as the idempotency key',
    () async {
      final action = await expenseAction();
      await service.processQueuedAction(action);
      expect(api.keys, [action.id]);
    },
  );

  test('replaying after a lost response creates exactly one record', () async {
    final action = await expenseAction();
    api.dropNextResponse = true;
    await expectLater(service.processQueuedAction(action), throwsA(anything));
    // The queue retries the same action later.
    await service.processQueuedAction(action);
    expect(api.keys, [action.id, action.id]);
    expect(api.records, 1);
  });

  test('different actions get different keys', () async {
    final first = await expenseAction();
    final second = await expenseAction();
    await service.processQueuedAction(first);
    await service.processQueuedAction(second);
    expect(api.keys, [first.id, second.id]);
    expect(api.records, 2);
  });
}
