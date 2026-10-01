import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/memory_doc_source.dart';

void main() {
  group('currentAccountingRoleProvider', () {
    test('returns the current membership accounting role', () async {
      final firestore = MemoryDocSource();
      await firestore.collection('memberships').doc('membership_1').set({
        'workspaceId': 'workspace_1',
        'userId': 'user_1',
        'role': 'accountingApproved',
      });

      final container = ProviderContainer(
        overrides: [
          docSourceProvider.overrideWithValue(firestore),
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        currentAccountingRoleProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final role = await container.read(currentAccountingRoleProvider.future);

      expect(role, AccountingAccessRoleType.accountingApproved);
    });

    test('returns null when membership is missing', () async {
      final firestore = MemoryDocSource();
      final container = ProviderContainer(
        overrides: [
          docSourceProvider.overrideWithValue(firestore),
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        currentAccountingRoleProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final role = await container.read(currentAccountingRoleProvider.future);

      expect(role, isNull);
    });
  });
}
