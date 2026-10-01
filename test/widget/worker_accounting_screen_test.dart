import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/common/data/domain_accounting_records_source.dart';
import 'package:buildtrack_app/features/common/presentation/screens/domain_accounting_records_screen.dart';
import 'package:buildtrack_app/features/workers/data/worker_accounting_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_accounting_record.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/worker_accounting_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory data for the screen (spec 004): the records list and the
/// maintained summary come from the local replica in the app.
class _Data {
  final records = <DomainRecord>[];
  WorkerAccountingSummary? summary;
}

class _FakeWorkerAccountingRepository extends Fake
    implements WorkerAccountingRepository {
  _FakeWorkerAccountingRepository(this._data);

  final _Data _data;

  @override
  Future<WorkerAccountingSummary?> fetchSummary({
    required String workspaceId,
    required String workerId,
  }) async => _data.summary;
}

void main() {
  testWidgets('member role sees deny state without worker ledger data', (
    tester,
  ) async {
    final data = _Data()..records.add(_workerRecord);

    await _pump(tester, data: data, role: AccountingAccessRoleType.member);
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
    final data = _Data()..records.add(_workerRecord);
    data.summary = WorkerAccountingSummary.fromMap('workspace_1_worker_1', {
      'workspaceId': 'workspace_1',
      'workerId': 'worker_1',
      'totalAmount': 12000,
      'confirmedPaid': 8000,
      'confirmedOutstanding': 4000,
      'unresolvedLegacyCount': 2,
      'recordCount': 120,
    });

    await _pump(tester, data: data, role: AccountingAccessRoleType.owner);
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
    final data = _Data();

    await _pump(tester, data: data, role: AccountingAccessRoleType.owner);
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
    final data = _Data();
    await tester.pumpWidget(
      _testApp(
        data: data,
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

final DomainRecord _workerRecord = (
  id: 'record_1',
  data: {
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
    'attachments': const <Map<String, dynamic>>[],
  },
);

Future<void> _pump(
  WidgetTester tester, {
  required _Data data,
  required AccountingAccessRoleType role,
}) {
  return tester.pumpWidget(
    _testApp(
      data: data,
      role: role,
      child: const WorkerAccountingScreen(
        workerId: 'worker_1',
        workerName: 'Worker One',
      ),
    ),
  );
}

Widget _testApp({
  required _Data data,
  required AccountingAccessRoleType role,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
      activeUserIdProvider.overrideWith((ref) => 'user_1'),
      domainAccountingRecordsProvider.overrideWith(
        (ref, query) => Stream.value(
          query.ownerId == 'worker_1' ? data.records : const <DomainRecord>[],
        ),
      ),
      workerAccountingRepositoryProvider.overrideWithValue(
        _FakeWorkerAccountingRepository(data),
      ),
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
