/// Read parity (spec 004, T033): the old Firestore repositories and the new
/// local-replica repositories must turn the same data into the same models.
///
/// One fixture is written to `fake_cloud_firestore` and, converted like the
/// migrator does, to the local replica. The Firestore side's model output is
/// the golden (`test/fixtures/read_parity/*.json`, written when missing or
/// when `UPDATE_READ_PARITY_GOLDENS=1`); both sides must match it. Once
/// Firestore is removed (T084) the goldens keep guarding the local side.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/features/contractors/data/contractor_accounting_repository.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:buildtrack_app/features/equipment/data/equipment_accounting_repository.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/notifications/data/notification_repository.dart';
import 'package:buildtrack_app/features/notifications/domain/notification_item.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/transport/data/transport_provider_accounting_repository.dart';
import 'package:buildtrack_app/features/workers/data/worker_accounting_repository.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_accounting_record.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../helpers/firestore_fixture.dart';
import '../helpers/local_db.dart';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

// ---------------------------------------------------------------- fixture

Timestamp _ts(int month, int day, [int hour = 8]) =>
    Timestamp.fromDate(DateTime.utc(2026, month, day, hour));

final _attachment = {
  'id': 'att1',
  'fileName': 'فاتورة.pdf',
  'storagePath': 'workspaces/ws_1/expenses/e1/att1_invoice.pdf',
  'contentType': 'application/pdf',
  'uploadedAt': _ts(5, 2),
  'size': 2048,
  'uploadedBy': 'u1',
};

final List<FixtureDoc> _fixture = [
  // Projects + their maintained metrics.
  for (final (id, created, archived, contract) in [
    ('p1', _ts(4, 1), false, 50000.0),
    ('p2', _ts(4, 10), false, null),
    ('p_arch', _ts(3, 1), true, 1000.0),
  ])
    (
      collection: 'projects',
      id: id,
      data: {
        'workspaceId': 'ws_1',
        'name': 'مشروع $id',
        'clientName': 'عميل',
        'contractValue': ?contract,
        'status': archived ? 'archived' : 'active',
        'completionPercentage': 40.0,
        'isArchived': archived,
        'location': 'الرياض',
        'description': 'وصف',
        'budgetLimit': 30000.0,
        'startDate': _ts(4, 1),
        'createdAt': created,
        'clientMutationId': 'm_$id',
      },
    ),
  (
    collection: 'project_metrics',
    id: 'p1',
    data: {
      'workspaceId': 'ws_1',
      'projectId': 'p1',
      'totalExpenses': 1200.5,
      'totalPayments': 5000.0,
      'netProfit': 3799.5,
      'riskLevel': 'low',
    },
  ),
  // Expenses (one archived, one in another project, one with attachment).
  for (final (id, project, day, archived) in [
    ('e1', 'p1', 1, false),
    ('e2', 'p1', 5, false),
    ('e_arch', 'p1', 6, true),
    ('e_other', 'p2', 7, false),
  ])
    (
      collection: 'expenses',
      id: id,
      data: {
        'workspaceId': 'ws_1',
        'projectId': project,
        'projectName': 'مشروع $project',
        'category': 'materials',
        'amount': 100.25 * day,
        'currency': 'SAR',
        'date': _ts(5, day),
        'notes': 'ملاحظة $id',
        'paymentMethod': 'cash',
        'paymentStatus': 'paid',
        'entityId': 'ent1',
        'entityName': 'مورد',
        'entityType': 'supplier',
        'isArchived': archived,
        'attachments': id == 'e1' ? [_attachment] : <Object>[],
        'createdAt': _ts(5, day, 9),
        'clientMutationId': 'm_$id',
      },
    ),
  // Payments.
  for (final (id, day, paid) in [('pay1', 2, null), ('pay2', 8, 300.0)])
    (
      collection: 'payments',
      id: id,
      data: {
        'workspaceId': 'ws_1',
        'projectId': 'p1',
        'amount': 1000.0,
        'date': _ts(5, day),
        'paymentMethod': 'transfer',
        'paymentStatus': paid == null ? 'paid' : 'partial',
        'paidAmount': ?paid,
        'description': 'دفعة $id',
        'entityName': 'عميل',
        'entityType': 'client',
        'isArchived': false,
        'attachments': <Object>[],
        'createdAt': _ts(5, day, 9),
      },
    ),
  // Workers + entries.
  for (final (id, status) in [('w1', 'active'), ('w2', 'inactive')])
    (
      collection: 'workers',
      id: id,
      data: {
        'workspaceId': 'ws_1',
        'name': 'عامل $id',
        'phoneNumber': '0500000000',
        'dailyWage': 150.0,
        'billingType': 'daily',
        'workerType': 'labor',
        'status': status,
        'notes': '',
        'isArchived': false,
        'createdAt': _ts(3, id == 'w1' ? 1 : 2),
      },
    ),
  for (final (id, day) in [('we1', 3), ('we2', 4)])
    (
      collection: 'worker_entries',
      id: id,
      data: {
        'workspaceId': 'ws_1',
        'workerId': 'w1',
        'projectId': 'p1',
        'daysWorked': 1.5,
        'dailyWage': 150.0,
        'totalCost': 225.0,
        'date': _ts(5, day),
        'notes': 'يوم $day',
        'isArchived': false,
        'attachments': <Object>[],
        'createdAt': _ts(5, day, 9),
      },
    ),
  // Entities.
  for (final (id, name, used) in [
    ('ent1', 'مورد', _ts(5, 7)),
    ('ent2', 'Contractor B', _ts(5, 3)),
  ])
    (
      collection: 'entities',
      id: id,
      data: {
        'workspaceId': 'ws_1',
        'name': name,
        'normalizedName': name.toLowerCase(),
        'type': id == 'ent1' ? 'supplier' : 'contractor',
        'createdAt': _ts(2, 1),
        'lastUsedAt': used,
        'defaultRate': 12.5,
        'rateUnit': 'hour',
        'attachments': <Object>[],
      },
    ),
  // The four accounting record types.
  for (final (collection, ownerField, owner) in [
    ('worker_accounting_records', 'workerId', 'w1'),
    ('contractor_accounting_records', 'contractorId', 'k1'),
    ('equipment_accounting_records', 'providerId', 'eq1'),
    ('transport_provider_accounting_records', 'providerId', 'tr1'),
  ])
    for (final day in [2, 9])
      (
        collection: collection,
        id: '${collection.split('_').first}_$day',
        data: {
          'workspaceId': 'ws_1',
          'projectId': 'p1',
          ownerField: owner,
          if (collection == 'worker_accounting_records')
            'workerName': 'عامل w1',
          if (collection == 'contractor_accounting_records')
            'contractorName': 'مقاول',
          if (collection.startsWith('equipment') ||
              collection.startsWith('transport'))
            'providerName': 'مزود',
          'description': 'سجل $day',
          'amount': 400.0 + day,
          if (collection == 'worker_accounting_records') 'paidAmount': 100.0,
          'date': _ts(5, day),
          'paymentMethod': 'cash',
          'paymentStatus': day == 2 ? 'paid' : 'partial',
          'notes': '',
          'attachments': <Object>[],
          'createdAt': _ts(5, day, 9),
        },
      ),
  // Summaries.
  (
    collection: 'worker_accounting_summaries',
    id: 'ws_1_w1',
    data: {
      'workspaceId': 'ws_1',
      'workerId': 'w1',
      'totalAmount': 811.0,
      'confirmedPaid': 200.0,
      'confirmedOutstanding': 611.0,
      'unresolvedLegacyCount': 0,
      'recordCount': 2,
    },
  ),
  // Both carry the ordering field: fake_cloud_firestore keeps documents that
  // lack an orderBy field, real Firestore drops them (the local source follows
  // real Firestore; covered in test/core/sync/doc_source_test.dart).
  for (final (id, latest) in [
    ('s1', '2026-05-07T00:00:00Z'),
    ('s2', '2026-05-03T00:00:00Z'),
  ])
    (
      collection: 'entity_summaries',
      id: id,
      data: {
        'workspaceId': 'ws_1',
        'projectId': 'p1',
        'entityName': 'كيان $id',
        'totalAmount': 900.5,
        'latestTransactionDate': latest,
      },
    ),
  // Notifications.
  for (final (id, target, day) in [
    ('n1', 'u1', 1),
    ('n2', 'u1', 4),
    ('n3', 'u2', 5),
  ])
    (
      collection: 'notifications',
      id: id,
      data: {
        'workspaceId': 'ws_1',
        'targetUserId': target,
        'type': 'budget',
        'title': 'تنبيه $id',
        'message': 'رسالة',
        'createdAt': _ts(5, day),
      },
    ),
];

// ------------------------------------------------------------ projections

Map<String, Object?> _att(Attachment a) => {
  'id': a.id,
  'fileName': a.fileName,
  'storagePath': a.storagePath,
  'contentType': a.contentType,
  'uploadedAt': a.uploadedAt,
  'downloadUrl': a.downloadUrl,
  'type': a.type,
  'size': a.size,
  'uploadedBy': a.uploadedBy,
};

Map<String, Object?> _project(Project p) => {
  'id': p.id,
  'workspaceId': p.workspaceId,
  'name': p.name,
  'clientName': p.clientName,
  'contractValue': p.contractValue,
  'status': p.status,
  'completionPercentage': p.completionPercentage,
  'totalExpenses': p.totalExpenses,
  'totalPayments': p.totalPayments,
  'netProfit': p.netProfit,
  'isArchived': p.isArchived,
  'clientMutationId': p.clientMutationId,
  'location': p.location,
  'description': p.description,
  'budgetLimit': p.budgetLimit,
  'startDate': p.startDate,
  'expectedEndDate': p.expectedEndDate,
};

Map<String, Object?> _expense(Expense e) => {
  'id': e.id,
  'workspaceId': e.workspaceId,
  'projectId': e.projectId,
  'projectName': e.projectName,
  'category': e.category,
  'amount': e.amount,
  'currency': e.currency,
  'date': e.date,
  'notes': e.notes,
  'purpose': e.purpose,
  'description': e.description,
  'supplierName': e.supplierName,
  'paymentMethod': e.paymentMethod,
  'paymentStatus': e.paymentStatus,
  'entityId': e.entityId,
  'entityName': e.entityName,
  'entityType': e.entityType,
  'inputMethod': e.inputMethod,
  'transcript': e.transcript,
  'source': e.source,
  'storagePath': e.storagePath,
  'attachments': e.attachments.map(_att).toList(),
  'isArchived': e.isArchived,
  'clientMutationId': e.clientMutationId,
};

Map<String, Object?> _payment(PaymentRecord p) => {
  'id': p.id,
  'workspaceId': p.workspaceId,
  'projectId': p.projectId,
  'amount': p.amount,
  'date': p.date,
  'paymentMethod': p.paymentMethod,
  'paymentStatus': p.paymentStatus,
  'paidAmount': p.paidAmount,
  'description': p.description,
  'notes': p.notes,
  'entityId': p.entityId,
  'entityName': p.entityName,
  'entityType': p.entityType,
  'attachments': p.attachments.map(_att).toList(),
  'isArchived': p.isArchived,
  'clientMutationId': p.clientMutationId,
};

Map<String, Object?> _worker(WorkerProfile w) => {
  'id': w.id,
  'workspaceId': w.workspaceId,
  'name': w.name,
  'phoneNumber': w.phoneNumber,
  'dailyWage': w.dailyWage,
  'billingType': w.billingType,
  'workerType': w.workerType,
  'notes': w.notes,
  'isArchived': w.isArchived,
  'status': w.status.name,
  'clientMutationId': w.clientMutationId,
};

Map<String, Object?> _entry(WorkerEntryRecord e) => {
  'id': e.id,
  'workspaceId': e.workspaceId,
  'workerId': e.workerId,
  'projectId': e.projectId,
  'daysWorked': e.daysWorked,
  'dailyWage': e.dailyWage,
  'totalCost': e.totalCost,
  'date': e.date,
  'notes': e.notes,
  'isArchived': e.isArchived,
  'attachments': e.attachments.map(_att).toList(),
  'clientMutationId': e.clientMutationId,
};

Map<String, Object?> _entity(AppEntity e) => {
  'id': e.id,
  'workspaceId': e.workspaceId,
  'name': e.name,
  'normalizedName': e.normalizedName,
  'type': e.type,
  'createdAt': e.createdAt,
  'attachments': e.attachments.map(_att).toList(),
  'lastUsedAt': e.lastUsedAt,
  'clientMutationId': e.clientMutationId,
  'defaultRate': e.defaultRate,
  'rateUnit': e.rateUnit,
  'phoneNumber': e.phoneNumber,
  'notes': e.notes,
};

/// The four accounting record types share this shape.
Map<String, Object?> _record({
  required String id,
  required String owner,
  required String ownerName,
  required double amount,
  required DateTime date,
  required String status,
  required String description,
  required List<Attachment> attachments,
  double? paidAmount,
}) => {
  'id': id,
  'owner': owner,
  'ownerName': ownerName,
  'amount': amount,
  'paidAmount': paidAmount,
  'date': date,
  'paymentStatus': status,
  'description': description,
  'attachments': attachments.map(_att).toList(),
};

Map<String, Object?> _notification(NotificationItem n) => {
  'id': n.id,
  'workspaceId': n.workspaceId,
  'targetUserId': n.targetUserId,
  'title': n.title,
  'message': n.message,
  'createdAt': n.createdAt,
  'readAt': n.readAt,
};

// ---------------------------------------------------------------- harness

/// The value a stream settles on: Firestore streams can emit before their
/// secondary reads (metrics, queue) arrive.
Future<T> _settled<T>(Stream<T> stream) async {
  final completer = Completer<void>();
  T? last;
  var seen = false;
  final sub = stream.listen((value) {
    last = value;
    seen = true;
  }, onError: completer.completeError);
  await Future.any([
    completer.future,
    Future<void>.delayed(const Duration(milliseconds: 400)),
  ]);
  unawaited(sub.cancel());
  if (!seen) throw StateError('Stream emitted nothing');
  return last as T;
}

final _update = Platform.environment['UPDATE_READ_PARITY_GOLDENS'] == '1';

/// Firestore output becomes the golden (when missing or updating); both
/// outputs must equal it.
void _expectParity(String name, Object? firestore, Object? local) {
  final file = File('test/fixtures/read_parity/$name.json');
  final firestoreJson = goldenJson(firestore);
  if (_update || !file.existsSync()) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(firestoreJson)}\n',
    );
  }
  final golden = jsonDecode(file.readAsStringSync());
  expect(
    jsonDecode(jsonEncode(firestoreJson)),
    golden,
    reason: '$name: Firestore repository drifted from its golden',
  );
  expect(
    jsonDecode(jsonEncode(goldenJson(local))),
    golden,
    reason: '$name: local repository differs from the Firestore golden',
  );
}

/// After the Firestore repositories are removed (T084/T085) the committed
/// goldens are the reference for the local repositories.
void _expectGolden(String name, Object? local) {
  final file = File('test/fixtures/read_parity/$name.json');
  final golden = jsonDecode(file.readAsStringSync());
  expect(
    jsonDecode(jsonEncode(goldenJson(local))),
    golden,
    reason: '$name: local repository differs from the Firestore golden',
  );
}

void main() {
  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;
  late FakeFirebaseFirestore firestore;
  late LocalTestDb local;
  late Future<PowerSyncDatabase> db;
  late _MockWorkspaceMutationService mutations;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('read_parity_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('offline_actions_read_parity');
    queue = OfflineActionQueue(box);
    mutations = _MockWorkspaceMutationService();
    firestore = FakeFirebaseFirestore();
    local = await LocalTestDb.open();
    db = Future.value(local.db);
    final rowsByTable = <String, List<Map<String, Object?>>>{};
    for (final doc in _fixture) {
      await firestore.collection(doc.collection).doc(doc.id).set(doc.data);
      rowsByTable
          .putIfAbsent(localTableFor(doc.collection), () => [])
          .add(firestoreDocToLocalRow(doc));
    }
    for (final entry in rowsByTable.entries) {
      await local.seedRows(entry.key, entry.value);
    }
  });

  tearDownAll(() async {
    await local.dispose();
    await box.close();
    await Hive.deleteBoxFromDisk('offline_actions_read_parity');
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('projects (with maintained metrics)', () async {
    final old = FirebaseProjectRepository(firestore, mutations, queue);
    final neu = LocalProjectRepository(firestore, mutations, queue, db);
    _expectParity(
      'projects',
      (await _settled(old.watchProjects('ws_1'))).map(_project).toList(),
      (await _settled(neu.watchProjects('ws_1'))).map(_project).toList(),
    );
    _expectParity(
      'project_p1',
      _project((await old.getProject('p1'))!),
      _project((await neu.getProject('p1'))!),
    );
  });

  test('expenses', () async {
    final old = FirebaseExpenseRepository(firestore, mutations, queue);
    final neu = LocalExpenseRepository(firestore, mutations, queue, db);
    _expectParity(
      'expenses_p1',
      (await _settled(old.watchExpenses('ws_1', 'p1'))).map(_expense).toList(),
      (await _settled(neu.watchExpenses('ws_1', 'p1'))).map(_expense).toList(),
    );
    _expectParity(
      'expense_e1',
      _expense((await old.getExpense('e1'))!),
      _expense((await neu.getExpense('e1'))!),
    );
  });

  test('payments', () async {
    final old = FirebasePaymentRepository(firestore, mutations, queue);
    final neu = LocalPaymentRepository(firestore, mutations, queue, db);
    _expectParity(
      'payments_p1',
      (await _settled(
        old.watchPayments('ws_1', projectId: 'p1'),
      )).map(_payment).toList(),
      (await _settled(
        neu.watchPayments('ws_1', projectId: 'p1'),
      )).map(_payment).toList(),
    );
  });

  test('workers and worker entries', () async {
    final oldWorkers = FirebaseWorkerRepository(firestore, mutations, queue);
    final newWorkers = LocalWorkerRepository(firestore, mutations, queue, db);
    _expectParity(
      'workers',
      (await _settled(oldWorkers.watchWorkers('ws_1'))).map(_worker).toList(),
      (await _settled(newWorkers.watchWorkers('ws_1'))).map(_worker).toList(),
    );
    final oldEntries = FirebaseWorkerEntryRepository(
      firestore,
      mutations,
      queue,
    );
    final newEntries = LocalWorkerEntryRepository(
      firestore,
      mutations,
      queue,
      db,
    );
    _expectParity(
      'worker_entries_w1',
      (await _settled(
        oldEntries.watchEntriesByWorker(workspaceId: 'ws_1', workerId: 'w1'),
      )).map(_entry).toList(),
      (await _settled(
        newEntries.watchEntriesByWorker(workspaceId: 'ws_1', workerId: 'w1'),
      )).map(_entry).toList(),
    );
  });

  test('entities', () async {
    final neu = LocalEntityRepository(db, mutations);
    _expectGolden(
      'entities',
      (await _settled(neu.watchEntities('ws_1'))).map(_entity).toList(),
    );
  });

  test('worker accounting records and summary', () async {
    final neu = WorkerAccountingRepository(db, mutations);
    Map<String, Object?> project(WorkerAccountingRecord r) => _record(
      id: r.id,
      owner: r.workerId,
      ownerName: r.workerName,
      amount: r.amount,
      paidAmount: r.paidAmount,
      date: r.date,
      status: r.paymentStatus,
      description: r.description,
      attachments: r.attachments,
    );
    _expectGolden(
      'worker_accounting_w1',
      (await neu.fetchForWorker(
        workspaceId: 'ws_1',
        workerId: 'w1',
      )).map(project).toList(),
    );
    Map<String, Object?> summary(WorkerAccountingSummary? s) => {
      'workspaceId': s?.workspaceId,
      'workerId': s?.workerId,
      'totalAmount': s?.totalAmount,
      'confirmedPaid': s?.confirmedPaid,
      'confirmedOutstanding': s?.confirmedOutstanding,
      'unresolvedLegacyCount': s?.unresolvedLegacyCount,
      'recordCount': s?.recordCount,
    };
    _expectGolden(
      'worker_accounting_summary_w1',
      summary(await neu.fetchSummary(workspaceId: 'ws_1', workerId: 'w1')),
    );
  });

  test('contractor, equipment and transport accounting records', () async {
    final newC = ContractorAccountingRepository(db, mutations);
    _expectGolden('contractor_accounting_k1', [
      for (final r in await newC.fetchForContractor(
        workspaceId: 'ws_1',
        contractorId: 'k1',
      ))
        _record(
          id: r.id,
          owner: r.contractorId,
          ownerName: r.contractorName,
          amount: r.amount,
          date: r.date,
          status: r.paymentStatus,
          description: r.description,
          attachments: r.attachments,
        ),
    ]);

    final newE = EquipmentAccountingRepository(db, mutations);
    Future<List<Map<String, Object?>>> equipment(
      EquipmentAccountingRepository repo,
    ) async => [
      for (final r in await repo.fetchForProvider(
        workspaceId: 'ws_1',
        providerId: 'eq1',
      ))
        _record(
          id: r.id,
          owner: r.providerId,
          ownerName: r.providerName,
          amount: r.amount,
          date: r.date,
          status: r.paymentStatus,
          description: r.description,
          attachments: r.attachments,
        ),
    ];
    _expectGolden('equipment_accounting_eq1', await equipment(newE));

    final newT = TransportProviderAccountingRepository(db, mutations);
    Future<List<Map<String, Object?>>> transport(
      TransportProviderAccountingRepository repo,
    ) async => [
      for (final r in await repo.fetchForProvider(
        workspaceId: 'ws_1',
        providerId: 'tr1',
      ))
        _record(
          id: r.id,
          owner: r.providerId,
          ownerName: r.providerName,
          amount: r.amount,
          date: r.date,
          status: r.paymentStatus,
          description: r.description,
          attachments: r.attachments,
        ),
    ];
    _expectGolden('transport_accounting_tr1', await transport(newT));
  });

  test('entity summaries through DocSource', () async {
    const query = DocQuery(
      'entity_summaries',
      equals: {'workspaceId': 'ws_1', 'projectId': 'p1'},
      orderBy: 'latestTransactionDate',
      descending: true,
      limit: 100,
    );
    List<Map<String, Object?>> docs(List<Doc> list) => [
      for (final d in list) {'id': d.id, ...d.data},
    ];
    _expectParity(
      'entity_summaries_p1',
      docs(await FirestoreDocSource(firestore).get(query)),
      docs(await LocalDocSource(db).get(query)),
    );
  });

  test('notifications', () async {
    final old = NotificationRepository(firestore);
    final neu = NotificationRepository.withSource(
      firestore,
      LocalDocSource(db),
    );
    _expectParity(
      'notifications_u1',
      (await _settled(
        old.watchTargeted(workspaceId: 'ws_1', userId: 'u1'),
      )).map(_notification).toList(),
      (await _settled(
        neu.watchTargeted(workspaceId: 'ws_1', userId: 'u1'),
      )).map(_notification).toList(),
    );
  });
}
