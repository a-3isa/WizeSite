import 'package:buildtrack_app/features/subscription/data/local_usage_quota_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usagePeriodKey uses UTC month boundaries', () {
    final utcNextMonth = DateTime.parse('2026-03-31T23:30:00-03:00');
    final utcSameMonth = DateTime.parse('2026-04-01T00:30:00+03:00');

    expect(usagePeriodKey(utcNextMonth), '202604');
    expect(usagePeriodKey(utcSameMonth), '202603');
  });
}
