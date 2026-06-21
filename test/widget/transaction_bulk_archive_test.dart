import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/common/presentation/controllers/transaction_bulk_archive_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selection state', () {
    test('toggle adds and removes ids and tracks selection mode', () {
      final c = TransactionBulkArchiveController();
      expect(c.state.isSelecting, isFalse);

      c.toggle('a');
      c.toggle('b');
      expect(c.state.selectedIds, {'a', 'b'});
      expect(c.state.isSelecting, isTrue);
      expect(c.state.selectedCount, 2);

      c.toggle('a');
      expect(c.state.selectedIds, {'b'});

      c.clear();
      expect(c.state.selectedIds, isEmpty);
      expect(c.state.isSelecting, isFalse);
      c.dispose();
    });

    test('selectAll selects the provided ids', () {
      final c = TransactionBulkArchiveController();
      c.selectAll(['x', 'y', 'z']);
      expect(c.state.selectedIds, {'x', 'y', 'z'});
      c.dispose();
    });
  });

  group('archiveSelected', () {
    test('does nothing and returns null with an empty selection', () async {
      final c = TransactionBulkArchiveController();
      final result = await c.archiveSelected(
        archiveOne: (_) async => const MutationResult(),
        confirm: (_) async => true,
      );
      expect(result, isNull);
      c.dispose();
    });

    test('cancellation skips archiving and preserves the selection', () async {
      final c = TransactionBulkArchiveController()..selectAll(['a', 'b']);
      var archiveCalls = 0;

      final result = await c.archiveSelected(
        archiveOne: (_) async {
          archiveCalls++;
          return const MutationResult();
        },
        confirm: (_) async => false,
      );

      expect(archiveCalls, 0);
      expect(result!.cancelled, isTrue);
      expect(c.state.selectedIds, {'a', 'b'});
      c.dispose();
    });

    test(
      'archives every selected record on success and clears selection',
      () async {
        final c = TransactionBulkArchiveController()
          ..selectAll(['a', 'b', 'c']);
        final archived = <String>[];

        final result = await c.archiveSelected(
          archiveOne: (id) async {
            archived.add(id);
            return const MutationResult();
          },
          confirm: (count) async {
            expect(count, 3);
            return true;
          },
        );

        expect(archived, containsAll(['a', 'b', 'c']));
        expect(result!.isComplete, isTrue);
        expect(result.succeeded.length, 3);
        expect(result.failed, isEmpty);
        expect(c.state.selectedIds, isEmpty);
        c.dispose();
      },
    );

    test('reports queued when the archive goes to the offline queue', () async {
      final c = TransactionBulkArchiveController()..selectAll(['a']);

      final result = await c.archiveSelected(
        archiveOne: (_) async => const MutationResult(queued: true),
        confirm: (_) async => true,
      );

      expect(result!.queued, isTrue);
      expect(result.isComplete, isTrue);
      c.dispose();
    });

    test('partial failure keeps failed ids selected for retry', () async {
      final c = TransactionBulkArchiveController()
        ..selectAll(['ok1', 'bad', 'ok2']);

      final result = await c.archiveSelected(
        archiveOne: (id) async {
          if (id == 'bad') throw Exception('archive rejected');
          return const MutationResult();
        },
        confirm: (_) async => true,
      );

      expect(result!.isComplete, isFalse);
      expect(result.isPartialFailure, isTrue);
      expect(result.succeeded, containsAll(['ok1', 'ok2']));
      expect(result.failed, ['bad']);
      expect(c.state.selectedIds, {
        'bad',
      }, reason: 'failed item stays selected');
      expect(c.state.isInProgress, isFalse);
      c.dispose();
    });
  });
}
