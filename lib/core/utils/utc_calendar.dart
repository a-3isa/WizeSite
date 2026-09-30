/// UTC calendar helpers matching Cloud Functions `startOfUtcDay` /
/// `startOfUtcWeek` / `withinUtcWeek` in `functions/src/index.ts`.
class UtcWeekBounds {
  const UtcWeekBounds({required this.start, required this.end});

  /// Monday 00:00:00.000 UTC.
  final DateTime start;

  /// Sunday 23:59:59.999 UTC.
  final DateTime end;
}

DateTime startOfUtcDay(DateTime input) {
  final utc = input.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

DateTime startOfUtcWeek(DateTime input) {
  final day = startOfUtcDay(input);
  final mondayOffset = day.weekday - DateTime.monday;
  return day.subtract(Duration(days: mondayOffset));
}

UtcWeekBounds utcIsoWeekBounds([DateTime? now]) {
  final start = startOfUtcWeek(now ?? DateTime.now());
  final end = start.add(
    const Duration(
      days: 6,
      hours: 23,
      minutes: 59,
      seconds: 59,
      milliseconds: 999,
    ),
  );
  return UtcWeekBounds(start: start, end: end);
}

UtcWeekBounds previousUtcIsoWeekBounds([DateTime? now]) {
  final current = utcIsoWeekBounds(now);
  final start = current.start.subtract(const Duration(days: 7));
  final end = current.start.subtract(const Duration(milliseconds: 1));
  return UtcWeekBounds(start: start, end: end);
}
