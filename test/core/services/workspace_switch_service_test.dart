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
  late WorkspaceMutationService service;
  late _MockCallableClient callableClient;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'workspace_switch_service_test_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('workspace_switch_service_test');
    callableClient = _MockCallableClient();
    final telemetry = _MockAppTelemetry();
    when(() => telemetry.log(any(), any())).thenAnswer((_) async {});
    service = WorkspaceMutationService(
      callableClient,
      OfflineActionQueue(box),
      telemetry,
    );
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('workspace_switch_service_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('persists selected active workspace through callable', () async {
    when(
      () => callableClient.call<String>(
        functionName: 'setActiveWorkspace',
        payload: {'workspaceId': 'shared_ws'},
        parseResult: any(named: 'parseResult'),
        defaultErrorMessage: 'Failed to switch workspace.',
      ),
    ).thenAnswer((invocation) async {
      final parser =
          invocation.namedArguments[#parseResult] as String Function(dynamic);
      return parser({'workspaceId': 'shared_ws'});
    });

    final workspaceId = await service.setActiveWorkspace(
      workspaceId: 'shared_ws',
    );

    expect(workspaceId, 'shared_ws');
    verify(
      () => callableClient.call<String>(
        functionName: 'setActiveWorkspace',
        payload: {'workspaceId': 'shared_ws'},
        parseResult: any(named: 'parseResult'),
        defaultErrorMessage: 'Failed to switch workspace.',
      ),
    ).called(1);
  });
}
