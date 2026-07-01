import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReportAccountingRow {
  const ReportAccountingRow({
    required this.date,
    required this.name,
    required this.description,
    required this.amount,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.attachmentCount,
  });

  final DateTime date;
  final String name;
  final String description;
  final double amount;
  final String paymentMethod;
  final String paymentStatus;
  final int attachmentCount;
}

pw.Widget reportSectionTitle(String text, pw.Font fontBold) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8, top: 18),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        font: fontBold,
        fontSize: 16,
        color: PdfColor.fromHex('#0F172A'),
      ),
    ),
  );
}

pw.Widget reportTwoColumnTable(List<List<String>> rows, pw.Font font) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300),
    columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1)},
    children: rows
        .map(
          (row) => pw.TableRow(
            children: row
                .map(
                  (cell) => pw.Padding(
                    padding: const pw.EdgeInsets.all(10),
                    child: pw.Text(
                      cell,
                      style: pw.TextStyle(font: font, fontSize: 11),
                    ),
                  ),
                )
                .toList(),
          ),
        )
        .toList(),
  );
}

pw.Widget reportDataTable({
  required List<String> headers,
  required List<List<String>> rows,
  required pw.Font font,
  required pw.Font fontBold,
}) {
  pw.TableRow buildRow(List<String> cells, {required bool header}) {
    return pw.TableRow(
      decoration: header
          ? const pw.BoxDecoration(color: PdfColors.grey200)
          : null,
      children: cells
          .map(
            (cell) => pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                cell,
                style: pw.TextStyle(
                  font: header ? fontBold : font,
                  fontSize: 9,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300),
    children: [
      buildRow(headers, header: true),
      ...rows.map((row) => buildRow(row, header: false)),
    ],
  );
}

double reportAccountingTotal(List<ReportAccountingRow> rows) {
  return rows.fold<double>(0, (sum, row) => sum + row.amount);
}

List<List<String>> reportAccountingDataRows({
  required AppLocalizations l10n,
  required List<ReportAccountingRow> rows,
  required String currency,
  required String locale,
  required DateFormat dateFormat,
}) {
  return rows
      .map(
        (row) => [
          dateFormat.format(row.date),
          row.name,
          row.description,
          Formatters.money(row.amount, currencyCode: currency, locale: locale),
          l10n.paymentMethodLabel(
            row.paymentMethod.isEmpty ? 'other' : row.paymentMethod,
          ),
          l10n.paymentStatusLabel(row.paymentStatus),
          '${row.attachmentCount}',
        ],
      )
      .toList(growable: false);
}
