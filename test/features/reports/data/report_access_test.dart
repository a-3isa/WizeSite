import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/services/accounting_access_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report exports are limited to accounting-approved roles', () {
    const service = AccountingAccessService();

    expect(
      service.canAccessFinancialData(AccountingAccessRoleType.owner),
      isTrue,
    );
    expect(
      service.canAccessFinancialData(AccountingAccessRoleType.admin),
      isTrue,
    );
    expect(
      service.canAccessFinancialData(
        AccountingAccessRoleType.accountingApproved,
      ),
      isTrue,
    );
    expect(
      service.canAccessFinancialData(AccountingAccessRoleType.member),
      isFalse,
    );
    expect(
      service.canAccessFinancialData(AccountingAccessRoleType.entryOnly),
      isFalse,
    );
  });
}
