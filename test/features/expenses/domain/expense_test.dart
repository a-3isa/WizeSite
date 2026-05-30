import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses structured accounting fields with attachment lifecycle', () {
    final expense = Expense.fromMap('expense_1', {
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'projectName': 'Tower',
      'category': 'materials',
      'amount': 1200,
      'currency': 'EGP',
      'date': '2026-05-27T00:00:00.000Z',
      'purpose': 'Concrete delivery',
      'description': 'Morning truck delivery',
      'notes': 'Gate 2',
      'supplierName': 'Acme Materials',
      'paymentMethod': 'cash',
      'paymentStatus': PaymentStatuses.partial,
      'entityId': 'entity_1',
      'entityName': 'Acme Materials',
      'entityType': 'supplier',
      'attachments': [
        {
          'id': 'attachment_1',
          'fileName': 'receipt.pdf',
          'storagePath': '',
          'contentType': 'application/pdf',
          'uploadedAt': '2026-05-27T01:00:00.000Z',
          'localPath': r'C:\pending\receipt.pdf',
          'uploadStatus': 'pending',
        },
      ],
    });

    expect(expense.purpose, 'Concrete delivery');
    expect(expense.description, 'Morning truck delivery');
    expect(expense.paymentStatus, PaymentStatuses.partial);
    expect(expense.entityType, 'supplier');
    expect(
      expense.attachments.single.uploadStatus,
      AttachmentUploadStatus.pending,
    );
  });

  test('uses safe backward-compatible defaults for old expense records', () {
    final expense = Expense.fromMap('expense_legacy', {
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'amount': 500,
      'date': '2026-05-27T00:00:00.000Z',
      'notes': 'Legacy note',
      'supplierName': 'Old Supplier',
    });

    expect(expense.category, 'other');
    expect(expense.paymentStatus, PaymentStatuses.unpaid);
    expect(expense.description, 'Legacy note');
    expect(expense.purpose, '');
    expect(expense.entityName, 'Old Supplier');
    expect(expense.entityType, 'supplier');
    expect(expense.attachments, isEmpty);
  });
}
