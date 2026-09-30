import 'package:buildtrack_app/core/pagination/local_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/local_db.dart';

void main() {
  late LocalTestDb local;

  setUp(() async {
    local = await LocalTestDb.open();
    // 5 expenses in ws_1 (two share a date to exercise the id tie-break), 1 in ws_2.
    await local.seedRows('expenses', [
      for (final (id, date) in [
        ('e1', '2026-05-01T00:00:00Z'),
        ('e2', '2026-05-02T00:00:00Z'),
        ('e3', '2026-05-03T00:00:00Z'),
        ('e4', '2026-05-03T00:00:00Z'),
        ('e5', '2026-05-04T00:00:00Z'),
      ])
        {
          'id': id,
          'workspace_id': 'ws_1',
          'project_id': 'p1',
          'amount': 1.0,
          'date': date,
        },
      {
        'id': 'x1',
        'workspace_id': 'ws_2',
        'project_id': 'p9',
        'amount': 1.0,
        'date': '2026-06-01T00:00:00Z',
      },
    ]);
  });
  tearDown(() => local.dispose());

  Future<LocalPage<String>> page(LocalPageCursor? cursor) =>
      fetchLocalPage<String>(
        local.db,
        table: 'expenses',
        where: 'workspace_id = ?',
        whereArgs: const ['ws_1'],
        orderBy: 'date',
        pageSize: 2,
        cursor: cursor,
        mapRow: (row) => '${row['id']}',
      );

  test(
    'pages newest-first with a stable id tie-break and no gaps or repeats',
    () async {
      final first = await page(null);
      expect(first.items, ['e5', 'e4']);
      expect(first.hasMore, isTrue);

      final second = await page(first.nextCursor);
      expect(second.items, ['e3', 'e2']);
      expect(second.hasMore, isTrue);

      final third = await page(second.nextCursor);
      expect(third.items, ['e1']);
      expect(third.hasMore, isFalse);
      expect(third.nextCursor, isNull);
    },
  );

  test('never returns rows outside the workspace scope', () async {
    final all = <String>[];
    LocalPageCursor? cursor;
    do {
      final p = await page(cursor);
      all.addAll(p.items);
      cursor = p.nextCursor;
    } while (cursor != null);
    expect(all, isNot(contains('x1')));
    expect(all, hasLength(5));
  });

  test('a row synced in mid-paging does not shift later pages', () async {
    final first = await page(null);
    await local.seedRows('expenses', [
      {
        'id': 'e6',
        'workspace_id': 'ws_1',
        'project_id': 'p1',
        'amount': 1.0,
        'date': '2026-05-05T00:00:00Z',
      },
    ]);
    final second = await page(first.nextCursor);
    expect(second.items, ['e3', 'e2'], reason: 'keyset, not OFFSET');
  });
}
