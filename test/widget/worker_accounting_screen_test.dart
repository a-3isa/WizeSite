import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/common/presentation/screens/domain_accounting_records_screen.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/worker_accounting_screen.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('member role sees deny state without worker ledger data', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedWorkerRecord(firestore);

    await _pump(
      tester,
      firestore: firestore,
      role: AccountingAccessRoleType.member,
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('permission to view financial reports'),
      findsOneWidget,
    );
    expect(find.text('Weekly settlement'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('owner sees maintained full-ledger worker summary', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await _seedWorkerRecord(firestore);
    await firestore
        .collection('worker_accounting_summaries')
        .doc('workspace_1_worker_1')
        .set({
          'workspaceId': 'workspace_1',
          'workerId': 'worker_1',
          'totalAmount': 12000,
          'confirmedPaid': 8000,
          'confirmedOutstanding': 4000,
          'unresolvedLegacyCount': 2,
          'recordCount': 120,
        });

    await _pump(
      tester,
      firestore: firestore,
      role: AccountingAccessRoleType.owner,
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirmed paid'), findsOneWidget);
    expect(find.textContaining('8,000 EGP'), findsOneWidget);
    expect(find.text('Outstanding'), findsOneWidget);
    expect(find.textContaining('4,000 EGP'), findsOneWidget);
    expect(
      find.textContaining('excluded from confirmed totals'),
      findsOneWidget,
    );
    expect(find.text('Weekly settlement'), findsOneWidget);
  });

  testWidgets('worker partial records expose a paid amount field', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();

    await _pump(
      tester,
      firestore: firestore,
      role: AccountingAccessRoleType.owner,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partial').last);
    await tester.pumpAndSettle();
    expect(find.text('Amount paid'), findsOneWidget);
  });

  testWidgets('generic domain accounting does not expose worker paid amount', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(
      _testApp(
        firestore: firestore,
        role: AccountingAccessRoleType.owner,
        child: const DomainAccountingRecordsScreen(
          titleKey: 'contractorAccounting',
          collectionName: 'contractor_accounting_records',
          ownerIdField: 'contractorId',
          ownerNameField: 'contractorName',
          ownerId: 'contractor_1',
          ownerName: 'Contractor One',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partial').last);
    await tester.pumpAndSettle();

    expect(find.text('Amount paid'), findsNothing);
  });
}

Future<void> _seedWorkerRecord(FakeFirebaseFirestore firestore) {
  return firestore.collection('worker_accounting_records').doc('record_1').set({
    'workspaceId': 'workspace_1',
    'projectId': 'project_1',
    'workerId': 'worker_1',
    'workerName': 'Worker One',
    'description': 'Weekly settlement',
    'amount': 250,
    'date': DateTime.utc(2026, 6, 1),
    'paymentMethod': 'cash',
    'paymentStatus': 'paid',
    'notes': '',
    'attachments': const [],
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeFirebaseFirestore firestore,
  required AccountingAccessRoleType role,
}) {
  return tester.pumpWidget(
    _testApp(
      firestore: firestore,
      role: role,
      child: const WorkerAccountingScreen(
        workerId: 'worker_1',
        workerName: 'Worker One',
      ),
    ),
  );
}

Widget _testApp({
  required FakeFirebaseFirestore firestore,
  required AccountingAccessRoleType role,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
      activeUserIdProvider.overrideWith((ref) => 'user_1'),
      firestoreProvider.overrideWithValue(firestore),
      currentAccountingRoleProvider.overrideWith((ref) => Stream.value(role)),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}
