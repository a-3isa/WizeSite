import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:buildtrack_app/features/reports/services/report_chart_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const exporter = ReportChartExporter();

  test('builds a category chart PDF from scoped totals', () async {
    final bytes = await exporter.buildCategoryChartPdf(
      title: 'Expenses by category',
      categoryTotals: const {'Materials': 1200, 'Labor': 800},
      currency: 'EGP',
    );

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(500));
  });

  test('builds a cashflow chart PDF from income and expense totals', () async {
    final bytes = await exporter.buildCashflowChartPdf(
      title: 'Cash flow',
      expenses: 900,
      income: 1500,
      currency: 'EGP',
    );

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(500));
  });

  test('builds a monthly flow chart PDF from monthly points', () async {
    final bytes = await exporter.buildMonthlyFlowChartPdf(
      title: 'Monthly flow',
      points: [
        MonthlyFlowData(
          month: DateTime.utc(2026, 5),
          expenses: 500,
          income: 800,
        ),
        MonthlyFlowData(
          month: DateTime.utc(2026, 6),
          expenses: 700,
          income: 1100,
        ),
      ],
      currency: 'EGP',
    );

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(500));
  });
}
