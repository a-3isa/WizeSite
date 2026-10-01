/// Makes a record map safe for the offline queue (stored as JSON)
/// and for the RPC API: dates become UTC ISO-8601 strings,
/// which the server parses back (spec 004).
Object? jsonSafe(Object? value) => switch (value) {
  final DateTime d => d.toUtc().toIso8601String(),
  final Map<dynamic, dynamic> m => <String, dynamic>{
    for (final entry in m.entries) '${entry.key}': jsonSafe(entry.value),
  },
  final Iterable<dynamic> l => [for (final v in l) jsonSafe(v)],
  _ => value,
};

Map<String, dynamic> jsonSafeMap(Map<String, dynamic> map) =>
    jsonSafe(map)! as Map<String, dynamic>;
