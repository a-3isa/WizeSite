import 'dart:io';

import 'package:buildtrack_app/core/services/app_telemetry.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockCallableClient extends Mock implements CallableClient {}

class _MockAppTelemetry extends Mock implements AppTelemetry {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;
  late _MockCallableClient client;
  late _MockAppTelemetry telemetry;
  late WorkspaceMutationService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'offline_conflict_resolution_test_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('offline_conflict_resolution_test');
    queue = OfflineActionQueue(box);
    client = _MockCallableClient();
    telemetry = _MockAppTelemetry();
    when(() => telemetry.log(any(), any())).thenAnswer((_) async {});
    when(
      () => client.call<void>(
        functionName: any(named: 'functionName'),
        payload: any(named: 'payload'),
        parseResult: any(named: 'parseResult'),
        defaultErrorMessage: any(named: 'defaultErrorMessage'),
        httpFunctionName: any(named: 'httpFunctionName'),
      ),
    ).thenAnswer((_) async {});
    service = WorkspaceMutationService(client, queue, telemetry);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('offline_conflict_resolution_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('skips older queued updates when a newer saved update exists', () async {
    final older = await queue.enqueue(
      type: OfflineActionTypes.updateExpense,
      clientSavedAt: DateTime.utc(2026, 5, 27, 8),
      payload: {
        'workspaceId': 'workspace_1',
        'expenseId': 'expense_1',
        'projectId': 'project_1',
        'category': 'materials',
        'amount': 100,
        'date': DateTime.utc(2026, 5, 27).toIso8601String(),
      },
    );
    final newer = await queue.enqueue(
      type: OfflineActionTypes.updateExpense,
      clientSavedAt: DateTime.utc(2026, 5, 27, 9),
      payload: {
        'workspaceId': 'workspace_1',
        'expenseId': 'expense_1',
        'projectId': 'project_1',
        'category': 'materials',
        'amount': 150,
        'date': DateTime.utc(2026, 5, 27).toIso8601String(),
      },
    );

    await service.processQueuedAction(older);
    verifyNever(
      () => client.call<void>(
        functionName: any(named: 'functionName'),
        payload: any(named: 'payload'),
        parseResult: any(named: 'parseResult'),
        defaultErrorMessage: any(named: 'defaultErrorMessage'),
        httpFunctionName: any(named: 'httpFunctionName'),
      ),
    );

    await service.processQueuedAction(newer);

    verify(
      () => client.call<void>(
        functionName: 'updateExpense',
        payload: any(named: 'payload'),
        parseResult: any(named: 'parseResult'),
        defaultErrorMessage: 'Failed to update expense.',
        httpFunctionName: any(named: 'httpFunctionName'),
      ),
    ).called(1);
  });
}
