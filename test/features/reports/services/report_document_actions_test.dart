import 'dart:typed_data';

import 'package:buildtrack_app/features/reports/services/report_document_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bytes = Uint8List.fromList(const [1, 2, 3, 4]);

  group('ReportDocumentActions.printDocument', () {
    test('reports completed when the print dialog succeeds', () async {
      Uint8List? seenBytes;
      String? seenName;
      final actions = ReportDocumentActions(
        printHandler: (b, name) async {
          seenBytes = b;
          seenName = name;
          return true;
        },
        shareHandler: (b, name) async => true,
      );

      final result = await actions.printDocument(bytes: bytes, name: 'Report');

      expect(result.status, DocumentActionStatus.completed);
      expect(result.isCompleted, isTrue);
      expect(seenBytes, bytes);
      expect(seenName, 'Report');
    });

    test('reports dismissed when the user cancels the dialog', () async {
      final actions = ReportDocumentActions(
        printHandler: (b, name) async => false,
        shareHandler: (b, name) async => true,
      );

      final result = await actions.printDocument(bytes: bytes, name: 'Report');

      expect(result.status, DocumentActionStatus.dismissed);
      expect(result.isDismissed, isTrue);
      expect(result.isCompleted, isFalse);
    });

    test(
      'reports failed and captures the error when printing throws',
      () async {
        final failure = Exception('platform channel exploded');
        final actions = ReportDocumentActions(
          printHandler: (b, name) async => throw failure,
          shareHandler: (b, name) async => true,
        );

        final result = await actions.printDocument(
          bytes: bytes,
          name: 'Report',
        );

        expect(result.status, DocumentActionStatus.failed);
        expect(result.isFailed, isTrue);
        expect(result.error, same(failure));
      },
    );
  });

  group('ReportDocumentActions.shareDocument', () {
    test('forwards bytes and filename and reports completed', () async {
      Uint8List? seenBytes;
      String? seenName;
      final actions = ReportDocumentActions(
        printHandler: (b, name) async => true,
        shareHandler: (b, name) async {
          seenBytes = b;
          seenName = name;
          return true;
        },
      );

      final result = await actions.shareDocument(
        bytes: bytes,
        filename: 'report.pdf',
      );

      expect(result.status, DocumentActionStatus.completed);
      expect(seenBytes, bytes);
      expect(seenName, 'report.pdf');
    });

    test('reports dismissed when sharing is cancelled', () async {
      final actions = ReportDocumentActions(
        printHandler: (b, name) async => true,
        shareHandler: (b, name) async => false,
      );

      final result = await actions.shareDocument(
        bytes: bytes,
        filename: 'report.pdf',
      );

      expect(result.status, DocumentActionStatus.dismissed);
    });

    test('reports failed when sharing throws', () async {
      final actions = ReportDocumentActions(
        printHandler: (b, name) async => true,
        shareHandler: (b, name) async => throw StateError('no share sheet'),
      );

      final result = await actions.shareDocument(
        bytes: bytes,
        filename: 'report.pdf',
      );

      expect(result.status, DocumentActionStatus.failed);
      expect(result.error, isA<StateError>());
    });
  });

  // T037: the expenses and payments lists hand their exported bytes to the same
  // adapter and must reach both the print and the share/save paths.
  group('expense and payment export handoff', () {
    final expenseBytes = Uint8List.fromList(const [10, 20, 30]);
    final paymentBytes = Uint8List.fromList(const [40, 50, 60]);

    test('expenses export routes through print and share', () async {
      final printed = <String>[];
      final shared = <String>[];
      final actions = ReportDocumentActions(
        printHandler: (b, name) async {
          printed.add(name);
          return true;
        },
        shareHandler: (b, name) async {
          shared.add(name);
          return true;
        },
      );

      final printResult = await actions.printDocument(
        bytes: expenseBytes,
        name: 'Expenses',
      );
      final shareResult = await actions.shareDocument(
        bytes: expenseBytes,
        filename: 'expenses.pdf',
      );

      expect(printResult.isCompleted, isTrue);
      expect(shareResult.isCompleted, isTrue);
      expect(printed, ['Expenses']);
      expect(shared, ['expenses.pdf']);
    });

    test('payments export routes through print and share', () async {
      final printed = <String>[];
      final shared = <String>[];
      final actions = ReportDocumentActions(
        printHandler: (b, name) async {
          printed.add(name);
          return true;
        },
        shareHandler: (b, name) async {
          shared.add(name);
          return true;
        },
      );

      await actions.printDocument(bytes: paymentBytes, name: 'Payments');
      await actions.shareDocument(
        bytes: paymentBytes,
        filename: 'payments.pdf',
      );

      expect(printed, ['Payments']);
      expect(shared, ['payments.pdf']);
    });
  });
}
