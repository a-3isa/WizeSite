import 'package:buildtrack_app/core/utils/utc_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UTC ISO week starts Monday 00:00 even just after UTC midnight', () {
    final mondayJustAfterMidnight = DateTime.utc(2026, 9, 14, 0, 30);
    final week = utcIsoWeekBounds(mondayJustAfterMidnight);
    expect(week.start, DateTime.utc(2026, 9, 14));
    expect(week.end, DateTime.utc(2026, 9, 20, 23, 59, 59, 999));

    final previousSunday = DateTime.utc(2026, 9, 13, 23, 30);
    expect(previousSunday.isBefore(week.start), isTrue);
    expect(previousSunday.isAfter(week.end), isFalse);
  });

  test('previous UTC ISO week is the Monday–Sunday before the current week', () {
    final wednesday = DateTime.utc(2026, 9, 16, 12);
    final previous = previousUtcIsoWeekBounds(wednesday);
    expect(previous.start, DateTime.utc(2026, 9, 7));
    expect(previous.end.isBefore(DateTime.utc(2026, 9, 14)), isTrue);
    expect(previous.end.isAfter(DateTime.utc(2026, 9, 13, 23)), isTrue);
  });
}
