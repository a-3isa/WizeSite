import 'package:buildtrack_app/core/sync/local_row.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expense row maps to the Firestore document shape the model reads', () {
    final map = localRowToMap('expenses', {
      'id': 'e1',
      'workspace_id': 'ws_1',
      'project_id': 'p1',
      'amount': 12.5,
      'date': '2026-05-02T00:00:00.000Z',
      'category': 'materials',
      'notes': 'حديد',
      'is_archived': 0,
      'attachments':
          '[{"id":"a1","fileName":"إيصال.jpg","storagePath":"receipts/u/x.jpg"}]',
      'legacy': '{"supplierName":"قديم","amount":999}',
    });

    expect(map['workspaceId'], 'ws_1');
    expect(map['projectId'], 'p1');
    expect(map['isArchived'], isFalse);
    expect(map['amount'], 12.5, reason: 'columns win over legacy');
    expect(map['supplierName'], 'قديم', reason: 'legacy fields restored');
    expect((map['attachments'] as List).single['fileName'], 'إيصال.jpg');
    expect(map.containsKey('legacy'), isFalse);

    final expense = Expense.fromMap('e1', map);
    expect(expense.amount, 12.5);
    expect(expense.date, DateTime.utc(2026, 5, 2));
    expect(expense.notes, 'حديد');
    expect(expense.attachments.single.fileName, 'إيصال.jpg');
  });

  test('NULL columns are absent, like missing Firestore fields', () {
    final map = localRowToMap('projects', {
      'id': 'p1',
      'workspace_id': 'ws_1',
      'name': 'Tower',
      'contract_value': null,
      'is_archived': 1,
    });
    expect(map.containsKey('contractValue'), isFalse);
    expect(map['isArchived'], isTrue);
    final project = Project.fromMap('p1', map);
    expect(project.contractValue, isNull, reason: 'feature 003: optional');
    expect(project.isArchived, isTrue);
  });

  test('renamed keys map back (active workspace, owner, member uid)', () {
    expect(
      localRowToMap('user_profiles', {
        'id': 'u1',
        'active_workspace_id': 'ws_1',
        'setup_completed': 1,
        'risk_alerts_enabled': 0,
      }),
      {
        'id': 'u1',
        'workspaceId': 'ws_1',
        'setupCompleted': true,
        'riskAlertsEnabled': false,
      },
    );
    expect(
      localRowToMap('workspaces', {'id': 'w', 'owner_uid': 'u1'})['ownerId'],
      'u1',
    );
    expect(
      localRowToMap('memberships', {'id': 'm', 'user_uid': 'u1'})['userId'],
      'u1',
    );
  });

  test('derived rows expose their payload fields at the top level', () {
    final map = localRowToMap('project_metrics', {
      'id': 'p1',
      'workspace_id': 'ws_1',
      'risk_level': 'low',
      'payload':
          '{"totalExpenses":300,"categoryTotals":{"worker":200},"projectName":"برج"}',
      'source_version': 3,
    });
    expect(map['totalExpenses'], 300);
    expect((map['categoryTotals'] as Map)['worker'], 200);
    expect(map['projectName'], 'برج');
    expect(map['workspaceId'], 'ws_1');
    expect(map.containsKey('payload'), isFalse);
  });

  test('malformed JSON in a column never throws; it is left out', () {
    final map = localRowToMap('expenses', {
      'id': 'e1',
      'attachments': '{not json',
      'legacy': 'nope',
    });
    expect(map.containsKey('attachments'), isFalse);
    expect(map['id'], 'e1');
  });
}
