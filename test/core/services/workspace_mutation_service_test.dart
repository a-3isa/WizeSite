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
  late _MockAppTelemetry telemetry;
  late WorkspaceMutationService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'workspace_mutation_service_test_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('workspace_mutation_service_test');
    queue = OfflineActionQueue(box);
    telemetry = _MockAppTelemetry();
    when(() => telemetry.log(any(), any())).thenAnswer((_) async {});
    service = WorkspaceMutationService(_MockCallableClient(), queue, telemetry);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('workspace_mutation_service_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'queues pending expense attachments as retryable upload actions',
    () async {
      final result = await service.createManualExpense(
        workspaceId: 'workspace_1',
        projectId: 'project_1',
        projectName: 'Project One',
        category: 'materials',
        amount: 250,
        currency: 'USD',
        date: DateTime.utc(2026, 5, 27),
        attachments: [
          {
            'id': 'attachment_1',
            'fileName': 'invoice.pdf',
            'localPath': r'C:\pending\invoice.pdf',
            'contentType': 'application/pdf',
            'size': 2048,
            'uploadStatus': 'pending',
          },
        ],
      );

      final actions = await queue.list(includeDeadLetters: true);

      expect(result.queued, isTrue);
      expect(actions.map((action) => action.type), [
        OfflineActionTypes.createExpense,
        OfflineActionQueueTypes.attachmentUpload,
      ]);
      expect(
        actions.last.payload[OfflineActionPayloadKeys.workspaceId],
        'workspace_1',
      );
      expect(
        actions.last.payload[OfflineActionPayloadKeys.ownerType],
        'expense',
      );
      expect(actions.last.payload[OfflineActionPayloadKeys.ownerId], result.id);
      expect(
        actions.last.payload[OfflineActionPayloadKeys.attachment]['localPath'],
        r'C:\pending\invoice.pdf',
      );
    },
  );

  test(
    'queues pending worker entry attachments as retryable upload actions',
    () async {
      final result = await service.createWorkerEntry(
        workspaceId: 'workspace_1',
        workerId: 'worker_1',
        projectId: 'project_1',
        daysWorked: 2,
        dailyWage: 150,
        date: DateTime.utc(2026, 6, 10),
        attachments: [
          {
            'id': 'worker_attachment_1',
            'fileName': 'signed-timesheet.pdf',
            'localPath': r'C:\pending\signed-timesheet.pdf',
            'contentType': 'application/pdf',
            'size': 4096,
            'uploadStatus': 'pending',
          },
        ],
      );

      final actions = await queue.list(includeDeadLetters: true);

      expect(result.queued, isTrue);
      expect(actions.map((action) => action.type), [
        OfflineActionTypes.createWorkerEntry,
        OfflineActionQueueTypes.attachmentUpload,
      ]);
      expect(
        actions.last.payload[OfflineActionPayloadKeys.workspaceId],
        'workspace_1',
      );
      expect(
        actions.last.payload[OfflineActionPayloadKeys.ownerType],
        'worker_entry',
      );
      expect(actions.last.payload[OfflineActionPayloadKeys.ownerId], result.id);
      expect(
        actions.last.payload[OfflineActionPayloadKeys.attachment]['fileName'],
        'signed-timesheet.pdf',
      );
    },
  );
}
