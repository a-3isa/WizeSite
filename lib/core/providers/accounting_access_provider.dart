import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/services/accounting_access_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final accountingAccessServiceProvider = Provider<AccountingAccessService>((ref) {
  return const AccountingAccessService();
});

final canAccessAccountingProvider =
    Provider.family<bool, AccountingAccessRoleType?>((ref, role) {
  return ref.read(accountingAccessServiceProvider).canAccessFinancialData(role);
});
