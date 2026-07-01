import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/settings/presentation/screens/workspace_settings_screen.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

void main() {
  Future<void> pumpWorkspaceSettings(
    WidgetTester tester, {
    required FakeFirebaseFirestore firestore,
    required WorkspaceMutationService workspaceService,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          activeUserIdProvider.overrideWith((ref) => 'owner_1'),
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          workspaceMutationServiceProvider.overrideWithValue(workspaceService),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: WorkspaceSettingsScreen(),
        ),
      ),
    );
  }

  testWidgets('shows workspace name crew and all privilege roles', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('workspaces').doc('workspace_1').set({
      'id': 'workspace_1',
      'name': 'Acme Sites',
      'ownerId': 'owner_1',
    });
    await firestore.collection('users').doc('owner_1').set({
      'id': 'owner_1',
      'fullName': 'Owner One',
      'email': 'owner@example.com',
      'photoUrl': '',
    });
    await firestore.collection('users').doc('member_1').set({
      'id': 'member_1',
      'fullName': 'Member One',
      'email': 'member@example.com',
      'photoUrl': '',
    });
    await firestore.collection('memberships').doc('workspace_1_owner_1').set({
      'workspaceId': 'workspace_1',
      'userId': 'owner_1',
      'role': 'owner',
    });
    await firestore.collection('memberships').doc('workspace_1_member_1').set({
      'workspaceId': 'workspace_1',
      'userId': 'member_1',
      'role': 'member',
    });

    await pumpWorkspaceSettings(
      tester,
      firestore: firestore,
      workspaceService: _MockWorkspaceMutationService(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Workspace name'), findsOneWidget);
    expect(find.text('Acme Sites'), findsWidgets);
    expect(find.text('Workspace Crew'), findsOneWidget);
    expect(find.text('Owner One'), findsOneWidget);
    expect(find.text('Member One'), findsOneWidget);

    await tester.tap(find.text('Member').last);
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Accounting approved'), findsOneWidget);
    expect(find.text('Entry only'), findsOneWidget);
  });

  testWidgets('renaming workspace does not reuse a disposed controller', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('workspaces').doc('workspace_1').set({
      'id': 'workspace_1',
      'name': 'Acme Sites',
      'ownerId': 'owner_1',
    });
    await firestore.collection('users').doc('owner_1').set({
      'id': 'owner_1',
      'fullName': 'Owner One',
      'email': 'owner@example.com',
      'photoUrl': '',
    });
    await firestore.collection('memberships').doc('workspace_1_owner_1').set({
      'workspaceId': 'workspace_1',
      'userId': 'owner_1',
      'role': 'owner',
    });

    await pumpWorkspaceSettings(
      tester,
      firestore: firestore,
      workspaceService: _MockWorkspaceMutationService(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Rename workspace'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Renamed Sites');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final workspace = await firestore
        .collection('workspaces')
        .doc('workspace_1')
        .get();
    expect(workspace.data()?['name'], 'Renamed Sites');
  });
}
