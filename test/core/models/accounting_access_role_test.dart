import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccountingAccessRole', () {
    test('identifies accounting-approved roles', () {
      expect(AccountingAccessRoleType.owner.canAccessAccounting, isTrue);
      expect(AccountingAccessRoleType.admin.canAccessAccounting, isTrue);
      expect(
        AccountingAccessRoleType.accountingApproved.canAccessAccounting,
        isTrue,
      );
      expect(AccountingAccessRoleType.member.canAccessAccounting, isFalse);
      expect(AccountingAccessRoleType.entryOnly.canAccessAccounting, isFalse);
    });

    test('parses unknown roles as member for safe default', () {
      final role = AccountingAccessRole.fromMap({
        'workspaceId': 'workspace_1',
        'userId': 'user_1',
        'role': 'unexpected',
      });

      expect(role.role, AccountingAccessRoleType.member);
      expect(role.canAccessAccounting, isFalse);
    });

    test('serializes role metadata', () {
      final role = AccountingAccessRole(
        workspaceId: 'workspace_1',
        userId: 'user_1',
        role: AccountingAccessRoleType.accountingApproved,
        grantedAt: DateTime.utc(2026, 5, 27),
        grantedBy: 'owner_1',
      );

      expect(role.toMap(), {
        'workspaceId': 'workspace_1',
        'userId': 'user_1',
        'role': 'accountingApproved',
        'grantedAt': '2026-05-27T00:00:00.000Z',
        'grantedBy': 'owner_1',
      });
    });
  });
}
