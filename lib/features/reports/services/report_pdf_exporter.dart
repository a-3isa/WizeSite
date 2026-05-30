import 'dart:typed_data';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportPdfExporter {
  const ReportPdfExporter();

  Future<Uint8List> buildProjectReportPdf({
    required AppLocalizations l10n,
    required Project project,
    required ReportMetrics metrics,
    required String currency,
  }) async {
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    final document = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final locale = l10n.locale.languageCode;

    pw.Widget sectionTitle(String text) {
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

    pw.Widget twoColumnTable(List<List<String>> rows) {
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300),
        columnWidths: const {
          0: pw.FlexColumnWidth(2),
          1: pw.FlexColumnWidth(1),
        },
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

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            l10n.t('buildozerFinancialReport'),
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 24,
              color: PdfColor.fromHex('#F59E0B'),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            l10n.t('projectReport'),
            style: pw.TextStyle(font: font, fontSize: 12),
          ),
          pw.SizedBox(height: 12),
          twoColumnTable([
            [l10n.t('project'), project.name],
            [l10n.t('status'), l10n.projectStatusLabel(project.status)],
            [l10n.t('generated'), dateFormat.format(DateTime.now())],
          ]),
          sectionTitle(l10n.t('currentSnapshot')),
          twoColumnTable([
            [
              l10n.t('totalIncome'),
              Formatters.money(metrics.totalIncome, currencyCode: currency, locale: locale),
            ],
            [
              l10n.t('totalExpenses'),
              Formatters.money(metrics.totalExpenses, currencyCode: currency, locale: locale),
            ],
            [
              l10n.t('netProfit'),
              Formatters.money(metrics.net, currencyCode: currency, locale: locale),
            ],
          ]),
          sectionTitle(l10n.t('expenseBreakdown')),
          twoColumnTable(
            metrics.categoryTotals.entries
                .map(
                  (entry) => [
                    l10n.expenseCategoryLabel(entry.key),
                    Formatters.money(entry.value, currencyCode: currency, locale: locale),
                  ],
                )
                .toList(),
          ),
          sectionTitle(l10n.t('monthlyCashFlow')),
          twoColumnTable(
            metrics.monthlyFlow
                .map(
                  (entry) => [
                    DateFormat('yyyy-MM').format(entry.month),
                    '${Formatters.money(entry.income, currencyCode: currency, locale: locale)} / ${Formatters.money(entry.expenses, currencyCode: currency, locale: locale)}',
                  ],
                )
                .toList(),
          ),
          sectionTitle(l10n.t('topWorkers')),
          twoColumnTable(
            metrics.topWorkers.isEmpty
                ? [
                    [l10n.t('workerName'), l10n.t('noDataYet')],
                  ]
                : metrics.topWorkers
                    .map(
                      (worker) => [
                        worker.name,
                        '${worker.totalDays.toStringAsFixed(1)} d / ${Formatters.money(worker.totalCost, currencyCode: currency, locale: locale)}',
                      ],
                    )
                    .toList(),
          ),
          sectionTitle(l10n.t('recentExpenses')),
          twoColumnTable(
            metrics.recentExpenses.isEmpty
                ? [
                    [l10n.t('expenses'), l10n.t('noDataYet')],
                  ]
                : metrics.recentExpenses
                    .map(
                      (expense) => [
                        '${DateFormat('yyyy-MM-dd').format(expense.date)} ${l10n.expenseCategoryLabel(expense.category)}',
                        Formatters.money(expense.amount, currencyCode: currency, locale: locale),
                      ],
                    )
                    .toList(),
          ),
          sectionTitle(l10n.t('recentPayments')),
          twoColumnTable(
            metrics.recentPayments.isEmpty
                ? [
                    [l10n.t('payments'), l10n.t('noDataYet')],
                  ]
                : metrics.recentPayments
                    .map(
                      (payment) => [
                        '${DateFormat('yyyy-MM-dd').format(payment.date)} ${l10n.paymentMethodLabel(payment.paymentMethod)}',
                        Formatters.money(payment.amount, currencyCode: currency, locale: locale),
                      ],
                    )
                    .toList(),
          ),
          pw.SizedBox(height: 18),
          pw.Center(
            child: pw.Text(
              l10n.t('generatedByBuildozer'),
              style: pw.TextStyle(font: font, fontSize: 10),
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  Future<Uint8List> buildEntitySummaryReportPdf({
    required AppLocalizations l10n,
    required List<EntitySummary> summaries,
    required String selectedType,
    required String currency,
  }) async {
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    final document = pw.Document();
    final locale = l10n.locale.languageCode;
    final filtered = selectedType == 'all'
        ? summaries
        : summaries.where((item) => item.entityType == selectedType).toList();

    pw.Widget sectionTitle(String text) {
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

    pw.Widget twoColumnTable(List<List<String>> rows) {
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300),
        columnWidths: const {
          0: pw.FlexColumnWidth(2),
          1: pw.FlexColumnWidth(1),
        },
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

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          final totalExpenses = filtered.fold<double>(
            0,
            (sum, item) => sum + item.totalExpenses,
          );
          final totalPayments = filtered.fold<double>(
            0,
            (sum, item) => sum + item.totalPayments,
          );
          final totalNet = totalPayments - totalExpenses;
          return [
            pw.Text(
              l10n.t('entitySummary'),
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 24,
                color: PdfColor.fromHex('#F59E0B'),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${l10n.t('entityType')}: ${selectedType == 'all' ? l10n.t('allTypes') : selectedType}',
              style: pw.TextStyle(font: font, fontSize: 12),
            ),
            pw.SizedBox(height: 12),
            twoColumnTable([
              [l10n.t('totalExpenses'), Formatters.money(totalExpenses, currencyCode: currency, locale: locale)],
              [l10n.t('totalPayments'), Formatters.money(totalPayments, currencyCode: currency, locale: locale)],
              [l10n.t('netProfit'), Formatters.money(totalNet, currencyCode: currency, locale: locale)],
              [l10n.t('topEntities'), filtered.length.toString()],
            ]),
            sectionTitle(l10n.t('entitySummary')),
            if (filtered.isEmpty)
              pw.Text(l10n.t('noDataYet'), style: pw.TextStyle(font: font, fontSize: 12))
            else
              twoColumnTable(
                filtered
                    .map(
                      (entity) => [
                        entity.entityName,
                        Formatters.money(entity.net, currencyCode: currency, locale: locale),
                      ],
                    )
                    .toList(),
              ),
            pw.SizedBox(height: 18),
            pw.Center(
              child: pw.Text(
                l10n.t('generatedByBuildozer'),
                style: pw.TextStyle(font: font, fontSize: 10),
              ),
            ),
          ];
        },
      ),
    );

    return document.save();
  }

  Future<Uint8List> buildWeeklyInsightsReportPdf({
    required AppLocalizations l10n,
    required DashboardWeeklyInsights insights,
    required String currency,
  }) async {
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    final document = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final locale = l10n.locale.languageCode;

    pw.Widget sectionTitle(String text) {
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

    pw.Widget twoColumnTable(List<List<String>> rows) {
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300),
        columnWidths: const {
          0: pw.FlexColumnWidth(2),
          1: pw.FlexColumnWidth(1),
        },
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

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            l10n.t('weeklyInsights'),
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 24,
              color: PdfColor.fromHex('#F59E0B'),
            ),
          ),
          pw.SizedBox(height: 4),
          twoColumnTable([
            [l10n.t('topEntity'), insights.topEntity],
            [l10n.t('topCategory'), insights.topCategory],
            [l10n.t('laborSummary'), Formatters.money(insights.laborTotal, currencyCode: currency, locale: locale)],
            [l10n.t('equipmentSummary'), Formatters.money(insights.equipmentTotal, currencyCode: currency, locale: locale)],
          ]),
          sectionTitle(l10n.t('paymentBreakdown')),
          if (insights.paymentSummary.isEmpty)
            pw.Text(l10n.t('noDataYet'), style: pw.TextStyle(font: font, fontSize: 12))
          else
            twoColumnTable(
              insights.paymentSummary.entries
                  .map(
                    (entry) => [
                      entry.key,
                      Formatters.money(entry.value, currencyCode: currency, locale: locale),
                    ],
                  )
                  .toList(),
            ),
          sectionTitle(l10n.t('recentTransactions')),
          if (insights.recentTransactions.isEmpty)
            pw.Text(l10n.t('noDataYet'), style: pw.TextStyle(font: font, fontSize: 12))
          else
            twoColumnTable(
              insights.recentTransactions
                  .map(
                    (transaction) => [
                      '${transaction.title} (${transaction.type})',
                      dateFormat.format(transaction.date),
                    ],
                  )
                  .toList(),
            ),
          pw.SizedBox(height: 18),
          pw.Center(
            child: pw.Text(
              l10n.t('generatedByBuildozer'),
              style: pw.TextStyle(font: font, fontSize: 10),
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  Future<Uint8List> buildCombinedReportPdf({
    required AppLocalizations l10n,
    required Project project,
    required ReportMetrics metrics,
    required DashboardWeeklyInsights insights,
    required String currency,
  }) async {
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    final document = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final locale = l10n.locale.languageCode;

    pw.Widget sectionTitle(String text) {
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

    pw.Widget twoColumnTable(List<List<String>> rows) {
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300),
        columnWidths: const {
          0: pw.FlexColumnWidth(2),
          1: pw.FlexColumnWidth(1),
        },
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

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            l10n.t('buildozerFinancialReport'),
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 24,
              color: PdfColor.fromHex('#F59E0B'),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            l10n.t('combinedReport'),
            style: pw.TextStyle(font: font, fontSize: 12),
          ),
          pw.SizedBox(height: 12),
          twoColumnTable([
            [l10n.t('project'), project.name],
            [l10n.t('status'), l10n.projectStatusLabel(project.status)],
            [l10n.t('generated'), dateFormat.format(DateTime.now())],
          ]),
          sectionTitle(l10n.t('currentSnapshot')),
          twoColumnTable([
            [l10n.t('totalIncome'), Formatters.money(metrics.totalIncome, currencyCode: currency, locale: locale)],
            [l10n.t('totalExpenses'), Formatters.money(metrics.totalExpenses, currencyCode: currency, locale: locale)],
            [l10n.t('netProfit'), Formatters.money(metrics.net, currencyCode: currency, locale: locale)],
          ]),
          sectionTitle(l10n.t('weeklyInsights')),
          twoColumnTable([
            [l10n.t('topEntity'), insights.topEntity],
            [l10n.t('topCategory'), insights.topCategory],
            [l10n.t('laborSummary'), Formatters.money(insights.laborTotal, currencyCode: currency, locale: locale)],
            [l10n.t('equipmentSummary'), Formatters.money(insights.equipmentTotal, currencyCode: currency, locale: locale)],
          ]),
          sectionTitle(l10n.t('paymentBreakdown')),
          if (insights.paymentSummary.isEmpty)
            pw.Text(l10n.t('noDataYet'), style: pw.TextStyle(font: font, fontSize: 12))
          else
            twoColumnTable(
              insights.paymentSummary.entries
                  .map(
                    (entry) => [
                      entry.key,
                      Formatters.money(entry.value, currencyCode: currency, locale: locale),
                    ],
                  )
                  .toList(),
            ),
          sectionTitle(l10n.t('recentTransactions')),
          if (insights.recentTransactions.isEmpty)
            pw.Text(l10n.t('noDataYet'), style: pw.TextStyle(font: font, fontSize: 12))
          else
            twoColumnTable(
              insights.recentTransactions
                  .map(
                    (transaction) => [
                      '${transaction.title} (${transaction.type})',
                      dateFormat.format(transaction.date),
                    ],
                  )
                  .toList(),
            ),
          pw.SizedBox(height: 18),
          pw.Center(
            child: pw.Text(
              l10n.t('generatedByBuildozer'),
              style: pw.TextStyle(font: font, fontSize: 10),
            ),
          ),
        ],
      ),
    );

    return document.save();
  }
}
