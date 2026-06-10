import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('currentAccountingRoleProvider', () {
    test('returns the current membership accounting role', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('memberships').doc('membership_1').set({
        'workspaceId': 'workspace_1',
        'userId': 'user_1',
        'role': 'accountingApproved',
      });

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
        ],
      );
      addTearDown(container.dispose);

      final role = await container.read(currentAccountingRoleProvider.future);

      expect(role, AccountingAccessRoleType.accountingApproved);
    });

    test('returns null when membership is missing', () async {
      final firestore = FakeFirebaseFirestore();
      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
        ],
      );
      addTearDown(container.dispose);

      final role = await container.read(currentAccountingRoleProvider.future);

      expect(role, isNull);
    });
  });
}
