import 'package:flutter_test/flutter_test.dart';

import 'local_db.dart';

void main() {
  test(
    'local test DB opens with the sync schema and round-trips rows',
    () async {
      final local = await LocalTestDb.open();
      addTearDown(local.dispose);

      await local.seedRows('expenses', [
        {
          'id': 'e1',
          'workspace_id': 'ws_1',
          'project_id': 'p1',
          'amount': 12.5,
          'category': 'materials',
          'notes': 'حديد تسليح',
          'attachments': '[]',
        },
      ]);

      final rows = await local.db.getAll(
        'SELECT id, amount, notes FROM expenses WHERE workspace_id = ?',
        ['ws_1'],
      );
      expect(rows, hasLength(1));
      expect(rows.first['amount'], 12.5);
      expect(rows.first['notes'], 'حديد تسليح');
    },
  );
}
