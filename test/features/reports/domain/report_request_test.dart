import 'package:buildtrack_app/features/reports/domain/report_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report request round-trips selected sections and dates', () {
    final request = ReportRequest(
      projectId: 'project_1',
      sections: const {
        ReportSection.expenses,
        ReportSection.payments,
        ReportSection.daily,
      },
      startDate: DateTime.utc(2026, 6, 1),
      endDate: DateTime.utc(2026, 6, 10),
    );

    final restored = ReportRequest.fromMap(request.toMap());

    expect(restored.projectId, 'project_1');
    expect(restored.includeExpenses, isTrue);
    expect(restored.includePayments, isTrue);
    expect(restored.includeDaily, isTrue);
    expect(restored.includeWeekly, isFalse);
    expect(restored.startDate, DateTime.utc(2026, 6, 1));
    expect(restored.endDate, DateTime.utc(2026, 6, 10));
  });

  test('report request defaults to expenses when sections are missing', () {
    final request = ReportRequest.fromMap({'projectId': 'project_1'});

    expect(request.includeExpenses, isTrue);
    expect(request.sections, {ReportSection.expenses});
  });
}
