import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/accounting_access_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final accountingAccessServiceProvider = Provider<AccountingAccessService>((
  ref,
) {
  return const AccountingAccessService();
});

final canAccessAccountingProvider =
    Provider.family<bool, AccountingAccessRoleType?>((ref, role) {
      return ref
          .read(accountingAccessServiceProvider)
          .canAccessFinancialData(role);
    });

final currentAccountingRoleProvider = StreamProvider<AccountingAccessRoleType?>(
  (ref) {
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final userId = ref.watch(activeUserIdProvider);
    if (workspaceId == null ||
        workspaceId.isEmpty ||
        userId == null ||
        userId.isEmpty) {
      return Stream.value(null);
    }

    return ref
        .watch(docSourceProvider)
        .watch(
          DocQuery(
            'memberships',
            equals: {'workspaceId': workspaceId, 'userId': userId},
            limit: 1,
          ),
        )
        .map((docs) {
          if (docs.isEmpty) {
            return null;
          }
          return AccountingAccessRoleType.fromValue(docs.first.data['role']);
        });
  },
);
