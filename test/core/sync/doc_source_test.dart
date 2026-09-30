import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/local_db.dart';

void main() {
  late LocalTestDb local;
  late LocalDocSource source;

  setUp(() async {
    local = await LocalTestDb.open();
    source = LocalDocSource(Future.value(local.db));
    await local.seedRows('expenses', [
      for (final (id, date, archived) in [
        ('e1', '2026-05-01 00:00:00Z', 0),
        ('e2', '2026-05-20 00:00:00Z', 0),
        ('e3', '2026-06-10 00:00:00Z', 0),
        ('e4', '2026-06-11 00:00:00Z', 1),
      ])
        {
          'id': id,
          'workspace_id': 'ws_1',
          'project_id': 'p1',
          'amount': 1.0,
          'date': date,
          'is_archived': archived,
        },
    ]);
    await local.seedRows('entity_summaries', [
      {
        'id': 's1',
        'workspace_id': 'ws_1',
        'project_id': 'p1',
        'payload':
            '{"entityName":"A","latestTransactionDate":"2026-06-01T00:00:00Z"}',
      },
      {
        'id': 's2',
        'workspace_id': 'ws_1',
        'project_id': 'p1',
        'payload':
            '{"entityName":"B","latestTransactionDate":"2026-06-05T00:00:00Z"}',
      },
      {
        'id': 's3',
        'workspace_id': 'ws_1',
        'project_id': 'p1',
        'payload': '{"entityName":"C"}',
      },
    ]);
    await local.seedRows('user_profiles', [
      {'id': 'u1', 'active_workspace_id': 'ws_1', 'full_name': 'مالك'},
    ]);
  });
  tearDown(() => local.dispose());

  test('equality (incl. bool), date range, order and limit', () async {
    final docs = await source.get(
      DocQuery(
        'expenses',
        equals: {'workspaceId': 'ws_1', 'isArchived': false},
        rangeField: 'date',
        rangeFrom: DateTime.utc(2026, 5, 10),
        rangeTo: DateTime.utc(2026, 6, 30),
        orderBy: 'date',
        descending: true,
        limit: 5,
      ),
    );
    expect(docs.map((d) => d.id), ['e3', 'e2']);
    expect(docs.first.data['workspaceId'], 'ws_1');
  });

  test(
    'ordering by a payload field of a derived table; missing field excluded',
    () async {
      final docs = await source.get(
        const DocQuery(
          'entity_summaries',
          equals: {'workspaceId': 'ws_1', 'projectId': 'p1'},
          orderBy: 'latestTransactionDate',
          descending: true,
        ),
      );
      expect(docs.map((d) => d.id), ['s2', 's1']);
      expect(docs.first.data['entityName'], 'B');
    },
  );

  test('users collection maps to profiles with renamed fields', () async {
    final doc = await source.getDoc('users', 'u1');
    expect(doc?.data['workspaceId'], 'ws_1');
    expect(doc?.data['fullName'], 'مالك');
    final byWorkspace = await source.get(
      const DocQuery('users', equals: {'workspaceId': 'ws_1'}),
    );
    expect(byWorkspace.single.id, 'u1');
  });

  test('watch and watchDoc are live', () async {
    final stream = source.watchDoc('expenses', 'e1');
    expect((await stream.first)?.data['amount'], 1.0);
    final updated = stream.where((d) => d?.data['amount'] == 5.0).first;
    await local.db.execute("UPDATE expenses SET amount = 5.0 WHERE id = 'e1'");
    expect((await updated)?.id, 'e1');
  });

  test('unknown collections and unsafe field names are rejected', () {
    expect(() => source.get(const DocQuery('secrets')), throwsArgumentError);
    expect(
      () =>
          source.get(const DocQuery('expenses', equals: {"x') OR 1=1 --": 1})),
      throwsArgumentError,
    );
  });
}
