import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/services/accounting_access_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccountingAccessService', () {
    const service = AccountingAccessService();

    test('allows owner admin and accounting-approved roles', () {
      for (final role in [
        AccountingAccessRoleType.owner,
        AccountingAccessRoleType.admin,
        AccountingAccessRoleType.accountingApproved,
      ]) {
        expect(service.canAccessFinancialData(role), isTrue);
      }
    });

    test('denies member entry-only and missing roles', () {
      expect(
        service.canAccessFinancialData(AccountingAccessRoleType.member),
        isFalse,
      );
      expect(
        service.canAccessFinancialData(AccountingAccessRoleType.entryOnly),
        isFalse,
      );
      expect(service.canAccessFinancialData(null), isFalse);
    });

    test('returns user-facing denial message', () {
      expect(
        service.deniedMessage,
        'You do not have permission to view financial reports, balances, or attachments.',
      );
    });
  });
}
