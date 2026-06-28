import 'package:buildtrack_app/features/workers/data/worker_accounting_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_accounting_record.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'worker accounting records persist attachments and list by worker',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repository = WorkerAccountingRepository(firestore);
      final record = WorkerAccountingRecord(
        id: 'record_1',
        workspaceId: 'workspace_1',
        projectId: 'project_1',
        workerId: 'worker_1',
        workerName: 'Worker One',
        description: 'Weekly labor settlement',
        amount: 250,
        date: DateTime.utc(2026, 5, 20),
        paymentMethod: 'cash',
        paymentStatus: 'paid',
        attachments: const [],
      );

      await repository.save(record);

      final records = await repository.fetchForWorker(
        workspaceId: 'workspace_1',
        workerId: 'worker_1',
      );
      expect(records, hasLength(1));
      expect(records.single.workerName, 'Worker One');
      expect(records.single.amount, 250);
    },
  );

  test('worker wage entries parse attachment metadata', () {
    final entry = WorkerEntryRecord.fromMap('entry_1', {
      'workspaceId': 'workspace_1',
      'workerId': 'worker_1',
      'projectId': 'project_1',
      'daysWorked': 1,
      'dailyWage': 150,
      'totalCost': 150,
      'date': DateTime.utc(2026, 6, 10).toIso8601String(),
      'notes': 'Signed day sheet',
      'isArchived': false,
      'attachments': [
        {
          'id': 'attach_1',
          'fileName': 'timesheet.pdf',
          'storagePath': 'attachments/timesheet.pdf',
          'contentType': 'application/pdf',
          'uploadedAt': DateTime.utc(2026, 6, 10).toIso8601String(),
          'downloadUrl': 'https://example.com/timesheet.pdf',
          'size': 1234,
        },
      ],
    });

    expect(entry.attachments, hasLength(1));
    expect(entry.attachments.single.fileName, 'timesheet.pdf');
    expect(entry.attachments.single.downloadUrl, contains('timesheet.pdf'));
  });

  WorkerAccountingRecord record({
    required double amount,
    required String paymentStatus,
    double? paidAmount,
  }) {
    return WorkerAccountingRecord(
      id: 'r',
      workspaceId: 'ws',
      projectId: 'p',
      workerId: 'w',
      workerName: 'W',
      description: 'd',
      amount: amount,
      date: DateTime.utc(2026, 6, 1),
      paymentMethod: 'cash',
      paymentStatus: paymentStatus,
      paidAmount: paidAmount,
    );
  }

  group('paid/unpaid/partial derivation', () {
    test('paid record is fully confirmed with no outstanding', () {
      final r = record(amount: 250, paymentStatus: 'paid');
      expect(r.confirmedPaidAmount, 250);
      expect(r.outstandingAmount, 0);
      expect(r.isLegacyPartialUnresolved, isFalse);
    });

    test('unpaid record has zero confirmed paid and full outstanding', () {
      final r = record(amount: 250, paymentStatus: 'unpaid');
      expect(r.confirmedPaidAmount, 0);
      expect(r.outstandingAmount, 250);
    });

    test('partial with paidAmount derives confirmed and outstanding', () {
      final r = record(amount: 250, paymentStatus: 'partial', paidAmount: 100);
      expect(r.confirmedPaidAmount, 100);
      expect(r.outstandingAmount, 150);
      expect(r.isLegacyPartialUnresolved, isFalse);
    });

    test('legacy partial without paidAmount is unresolved', () {
      final r = record(amount: 250, paymentStatus: 'partial');
      expect(r.isLegacyPartialUnresolved, isTrue);
      expect(r.confirmedPaidAmount, isNull);
      expect(r.outstandingAmount, isNull);
    });

    test('out-of-range partial paidAmount is unresolved (not clamped)', () {
      // >= amount and <= 0 are invalid → treated as unresolved, matching the
      // backend recompute (never fabricated by clamping).
      expect(
        record(
          amount: 250,
          paymentStatus: 'partial',
          paidAmount: 250,
        ).confirmedPaidAmount,
        isNull,
      );
      expect(
        record(
          amount: 250,
          paymentStatus: 'partial',
          paidAmount: 300,
        ).isLegacyPartialUnresolved,
        isTrue,
      );
      expect(
        record(
          amount: 250,
          paymentStatus: 'partial',
          paidAmount: 0,
        ).confirmedPaidAmount,
        isNull,
      );
    });
  });

  group('paidAmount validation', () {
    String? validate(String status, double amount, double? paid) =>
        WorkerAccountingRecord.validatePaidAmount(
          paymentStatus: status,
          amount: amount,
          paidAmount: paid,
        );

    test('not required for non-partial statuses', () {
      expect(validate('paid', 250, null), isNull);
      expect(validate('unpaid', 250, null), isNull);
    });

    test('required for a new partial record', () {
      expect(validate('partial', 250, null), 'workerPaidAmountRequired');
    });

    test('must be greater than zero and less than the amount', () {
      expect(validate('partial', 250, 0), 'workerPaidAmountTooLow');
      expect(validate('partial', 250, -5), 'workerPaidAmountTooLow');
      expect(validate('partial', 250, 250), 'workerPaidAmountTooHigh');
      expect(validate('partial', 250, 300), 'workerPaidAmountTooHigh');
    });

    test('accepts a valid partial amount', () {
      expect(validate('partial', 250, 100), isNull);
    });
  });

  group('confirmed totals exclude unresolved legacy partials', () {
    test('aggregates paid/outstanding and counts unresolved', () {
      final totals = WorkerAccountingTotals.fromRecords([
        record(amount: 100, paymentStatus: 'paid'),
        record(amount: 200, paymentStatus: 'unpaid'),
        record(amount: 300, paymentStatus: 'partial', paidAmount: 120),
        record(amount: 400, paymentStatus: 'partial'), // unresolved legacy
      ]);

      // paid: 100 + 120 = 220
      expect(totals.confirmedPaid, 220);
      // outstanding: 0 + 200 + 180 = 380 (legacy excluded)
      expect(totals.confirmedOutstanding, 380);
      // total amount is fully known for all records
      expect(totals.totalAmount, 1000);
      expect(totals.unresolvedLegacyCount, 1);
    });
  });

  test('paidAmount round-trips through the map', () {
    final map = record(
      amount: 250,
      paymentStatus: 'partial',
      paidAmount: 100,
    ).toMap();
    expect(map['paidAmount'], 100);
    final parsed = WorkerAccountingRecord.fromMap('r', map);
    expect(parsed.paidAmount, 100);
    expect(parsed.confirmedPaidAmount, 100);
  });

  group('maintained summary consumer (exact totals beyond the page cap)', () {
    test('parses a maintained summary document', () {
      final summary = WorkerAccountingSummary.fromMap('ws_w1', {
        'workspaceId': 'ws',
        'workerId': 'w1',
        'totalAmount': 12000,
        'confirmedPaid': 8000,
        'confirmedOutstanding': 3500,
        'unresolvedLegacyCount': 2,
        'recordCount': 120,
      });

      expect(summary.totalAmount, 12000);
      expect(summary.confirmedPaid, 8000);
      expect(summary.confirmedOutstanding, 3500);
      expect(summary.unresolvedLegacyCount, 2);
      expect(summary.recordCount, 120);
      expect(summary.hasUnresolvedLegacy, isTrue);
    });

    test(
      'reads exact totals over more than 50 records, not a 50-row page',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = WorkerAccountingRepository(firestore);

        // The maintained summary is computed over the full ledger (120 records),
        // independent of the 50-record fetch cap.
        await firestore
            .collection('worker_accounting_summaries')
            .doc('ws_w1')
            .set({
              'workspaceId': 'ws',
              'workerId': 'w1',
              'totalAmount': 12000,
              'confirmedPaid': 8000,
              'confirmedOutstanding': 4000,
              'unresolvedLegacyCount': 0,
              'recordCount': 120,
            });

        final summary = await repository.fetchSummary(
          workspaceId: 'ws',
          workerId: 'w1',
        );

        expect(summary, isNotNull);
        expect(summary!.recordCount, 120);
        expect(summary.confirmedPaid, 8000);
        expect(summary.confirmedOutstanding, 4000);
      },
    );

    test('returns null when no maintained summary exists yet', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = WorkerAccountingRepository(firestore);

      final summary = await repository.fetchSummary(
        workspaceId: 'ws',
        workerId: 'missing',
      );

      expect(summary, isNull);
    });
  });
}
