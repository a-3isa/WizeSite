import 'dart:convert';

/// Boolean columns: SQLite stores them as 0/1 (see server/migrations/*.sql).
const _booleanColumns = {
  'is_archived',
  'setup_completed',
  'risk_alerts_enabled',
  'is_auto_renewing',
};

/// Columns holding JSON text in the local replica.
const _jsonColumns = {'attachments', 'items', 'legacy', 'payload'};

/// Keys renamed by the migration (data-model.md), mapped back to the
/// Firestore field names the models read.
const _renames = {
  'active_workspace_id': 'workspaceId',
  'owner_uid': 'ownerId',
  'user_uid': 'userId',
};

String _camelCase(String column) => column.replaceAllMapped(
  RegExp('_([a-z])'),
  (m) => m.group(1)!.toUpperCase(),
);

Object? _decodeJson(Object? value) {
  if (value is! String) return value;
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

/// Turns a row of the local PowerSync replica into the map shape of the
/// original Firestore document, so the existing `Model.fromMap(id, map)`
/// constructors read it unchanged (spec 004, tasks.md T041):
///
/// - snake_case → camelCase, plus the three renamed keys;
/// - 0/1 → bool for boolean columns;
/// - JSON text columns decoded; `legacy` fields restored underneath, so
///   mapped columns win; derived rows' `payload` spread to the top level;
/// - NULL columns left out, like missing Firestore fields.
///
/// Money stays a double, exactly as the Firestore models read it.
Map<String, dynamic> localRowToMap(String table, Map<String, Object?> row) {
  final result = <String, dynamic>{};

  final legacy = _decodeJson(row['legacy']);
  if (legacy is Map) {
    result.addAll(Map<String, dynamic>.from(legacy));
  }
  final payload = _decodeJson(row['payload']);
  if (payload is Map) {
    result.addAll(Map<String, dynamic>.from(payload));
  }

  for (final entry in row.entries) {
    final column = entry.key;
    final value = entry.value;
    if (value == null || column == 'legacy' || column == 'payload') {
      continue;
    }
    final key = _renames[column] ?? _camelCase(column);
    if (_booleanColumns.contains(column)) {
      result[key] = value == 1 || value == true;
    } else if (_jsonColumns.contains(column)) {
      final decoded = _decodeJson(value);
      if (decoded != null) result[key] = decoded;
    } else {
      result[key] = value;
    }
  }
  return result;
}
