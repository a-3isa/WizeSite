import 'dart:typed_data';

import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportChartExporter {
  const ReportChartExporter();

  Future<Uint8List> buildCategoryChartPdf({
    required String title,
    required Map<String, double> categoryTotals,
    required String currency,
  }) {
    return _buildBarDocument(
      title: title,
      series: categoryTotals.entries
          .map((entry) => _ChartValue(entry.key, entry.value))
          .toList(growable: false),
      currency: currency,
      color: PdfColors.orange700,
    );
  }

  Future<Uint8List> buildCashflowChartPdf({
    required String title,
    required double expenses,
    required double income,
    required String currency,
  }) {
    return _buildBarDocument(
      title: title,
      series: [
        _ChartValue('Expenses', expenses),
        _ChartValue('Income', income),
      ],
      currency: currency,
      color: PdfColors.blue700,
    );
  }

  Future<Uint8List> buildMonthlyFlowChartPdf({
    required String title,
    required List<MonthlyFlowData> points,
    required String currency,
  }) {
    final series = <_ChartValue>[];
    for (final point in points) {
      final month =
          '${point.month.year}-${point.month.month.toString().padLeft(2, '0')}';
      series
        ..add(_ChartValue('$month expenses', point.expenses))
        ..add(_ChartValue('$month income', point.income));
    }
    return _buildBarDocument(
      title: title,
      series: series,
      currency: currency,
      color: PdfColors.teal700,
    );
  }

  Future<Uint8List> _buildBarDocument({
    required String title,
    required List<_ChartValue> series,
    required String currency,
    required PdfColor color,
  }) async {
    final document = pw.Document();
    final font = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();
    final maxValue = series.fold<double>(
      0,
      (current, item) => item.value > current ? item.value : current,
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (context) => [
          pw.Text(title, style: pw.TextStyle(font: boldFont, fontSize: 20)),
          pw.SizedBox(height: 24),
          if (series.isEmpty)
            pw.Text('No data')
          else
            ...series.map(
              (item) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 14),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${item.label}: ${item.value.toStringAsFixed(2)} $currency',
                    ),
                    pw.SizedBox(height: 4),
                    pw.Container(
                      height: 14,
                      width: maxValue <= 0
                          ? 0
                          : 480 * (item.value / maxValue).clamp(0, 1),
                      color: color,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    return document.save();
  }
}

class _ChartValue {
  const _ChartValue(this.label, this.value);

  final String label;
  final double value;
}
