import 'package:buildtrack_app/core/models/accounting_access_role.dart';

class AccountingAccessService {
  const AccountingAccessService();

  String get deniedMessage {
    return 'You do not have permission to view financial reports, balances, or attachments.';
  }

  bool canAccessFinancialData(AccountingAccessRoleType? role) {
    return role?.canAccessAccounting ?? false;
  }

  bool canAccessRole(AccountingAccessRole? accessRole) {
    return canAccessFinancialData(accessRole?.role);
  }
}
