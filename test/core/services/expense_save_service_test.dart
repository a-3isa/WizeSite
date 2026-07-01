import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/services/expense_save_service.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

void main() {
  test('saveVoiceExpense forwards pending attachment metadata', () async {
    final mutationService = _MockWorkspaceMutationService();
    final service = ExpenseSaveService(mutationService);
    final date = DateTime.utc(2026, 5, 27);
    final attachment = Attachment(
      id: 'attachment_1',
      fileName: 'voice-receipt.pdf',
      storagePath: '',
      downloadUrl: '',
      contentType: 'application/pdf',
      size: 2048,
      uploadedAt: date,
      localPath: r'C:\pending\voice-receipt.pdf',
      uploadStatus: AttachmentUploadStatus.pending,
    );

    when(
      () => mutationService.createManualExpense(
        workspaceId: any(named: 'workspaceId'),
        projectId: any(named: 'projectId'),
        projectName: any(named: 'projectName'),
        category: any(named: 'category'),
        amount: any(named: 'amount'),
        currency: any(named: 'currency'),
        date: any(named: 'date'),
        notes: any(named: 'notes'),
        supplierName: any(named: 'supplierName'),
        entityId: any(named: 'entityId'),
        entityName: any(named: 'entityName'),
        paymentMethod: any(named: 'paymentMethod'),
        inputMethod: any(named: 'inputMethod'),
        transcript: any(named: 'transcript'),
        source: any(named: 'source'),
        storagePath: any(named: 'storagePath'),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) async => const MutationResult(id: 'expense_1'));

    final id = await service.saveVoiceExpense(
      workspaceId: 'workspace_1',
      projectId: 'project_1',
      projectName: 'Project One',
      amount: 99,
      currency: 'USD',
      category: 'materials',
      date: date,
      notes: 'voice note',
      transcript: 'receipt for materials',
      source: 'voice',
      storagePath: 'voice/path.m4a',
      attachments: [attachment],
    );

    expect(id, 'expense_1');
    final captured =
        verify(
              () => mutationService.createManualExpense(
                workspaceId: 'workspace_1',
                projectId: 'project_1',
                projectName: 'Project One',
                category: 'materials',
                amount: 99,
                currency: 'USD',
                date: date,
                notes: 'voice note',
                supplierName: '',
                entityId: null,
                entityName: null,
                paymentMethod: '',
                inputMethod: 'voice',
                transcript: 'receipt for materials',
                source: 'voice',
                storagePath: 'voice/path.m4a',
                attachments: captureAny(named: 'attachments'),
              ),
            ).captured.single
            as List<Map<String, dynamic>>;
    expect(captured.single['localPath'], r'C:\pending\voice-receipt.pdf');
    expect(captured.single['uploadStatus'], 'pending');
  });
}
