import 'dart:typed_data';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/features/contractors/domain/contractor_accounting_record.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/equipment/domain/equipment_accounting_record.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_totals.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:buildtrack_app/features/reports/services/report_pdf_sections.dart';
import 'package:buildtrack_app/features/transport/domain/transport_provider_accounting_record.dart';
import 'package:buildtrack_app/features/workers/domain/worker_accounting_record.dart';
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
              Formatters.money(
                metrics.totalIncome,
                currencyCode: currency,
                locale: locale,
              ),
            ],
            [
              l10n.t('totalExpenses'),
              Formatters.money(
                metrics.totalExpenses,
                currencyCode: currency,
                locale: locale,
              ),
            ],
            [
              l10n.t('netProfit'),
              Formatters.money(
                metrics.net,
                currencyCode: currency,
                locale: locale,
              ),
            ],
          ]),
          sectionTitle(l10n.t('expenseBreakdown')),
          twoColumnTable(
            metrics.categoryTotals.entries
                .map(
                  (entry) => [
                    l10n.expenseCategoryLabel(entry.key),
                    Formatters.money(
                      entry.value,
                      currencyCode: currency,
                      locale: locale,
                    ),
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
                          Formatters.money(
                            expense.amount,
                            currencyCode: currency,
                            locale: locale,
                          ),
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
                          Formatters.money(
                            payment.amount,
                            currencyCode: currency,
                            locale: locale,
                          ),
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

  Future<Uint8List> buildExpensesListPdf({
    required AppLocalizations l10n,
    required String projectName,
    required List<Expense> expenses,
    required String currency,
    DateTime? startDate,
    DateTime? endDate,
    String? filterSummary,
  }) async {
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    final document = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd');
    final dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
    final locale = l10n.locale.languageCode;

    final total = sumExpenseAmounts(expenses);
    final categoryTotals = expenseCategoryTotals(expenses);
    final methodTotals = expensePaymentMethodTotals(expenses);

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

    pw.Widget dataTable(List<String> headers, List<List<String>> rows) {
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

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            l10n.t('exportExpenses'),
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 22,
              color: PdfColor.fromHex('#F59E0B'),
            ),
          ),
          pw.SizedBox(height: 10),
          twoColumnTable([
            [l10n.t('project'), projectName.isEmpty ? '-' : projectName],
            if (startDate != null || endDate != null)
              [
                l10n.t('dateRange'),
                '${startDate != null ? dateFormat.format(startDate) : '...'} - ${endDate != null ? dateFormat.format(endDate) : '...'}',
              ],
            if (filterSummary != null && filterSummary.isNotEmpty)
              [l10n.t('filtersApplied'), filterSummary],
            [l10n.t('generated'), dateTimeFormat.format(DateTime.now())],
            [
              l10n.t('totalExpenses'),
              Formatters.money(total, currencyCode: currency, locale: locale),
            ],
            [l10n.t('transactions'), '${expenses.length}'],
          ]),
          sectionTitle(l10n.t('expenseBreakdown')),
          twoColumnTable(
            categoryTotals.isEmpty
                ? [
                    [l10n.t('category'), l10n.t('noDataYet')],
                  ]
                : categoryTotals.entries
                      .map(
                        (entry) => [
                          l10n.expenseCategoryLabel(entry.key),
                          Formatters.money(
                            entry.value,
                            currencyCode: currency,
                            locale: locale,
                          ),
                        ],
                      )
                      .toList(),
          ),
          sectionTitle(l10n.t('paymentBreakdown')),
          twoColumnTable(
            methodTotals.isEmpty
                ? [
                    [l10n.t('paymentMethod'), l10n.t('noDataYet')],
                  ]
                : methodTotals.entries
                      .map(
                        (entry) => [
                          l10n.paymentMethodLabel(entry.key),
                          Formatters.money(
                            entry.value,
                            currencyCode: currency,
                            locale: locale,
                          ),
                        ],
                      )
                      .toList(),
          ),
          sectionTitle(l10n.t('expenseList')),
          dataTable(
            [
              l10n.t('date'),
              l10n.t('category'),
              l10n.t('entityName'),
              l10n.t('amount'),
              l10n.t('paymentMethod'),
              l10n.t('paymentStatus'),
              l10n.t('attachments'),
            ],
            expenses
                .map(
                  (item) => [
                    dateFormat.format(item.date),
                    l10n.expenseCategoryLabel(item.category),
                    item.entityName.isNotEmpty
                        ? item.entityName
                        : item.supplierName,
                    Formatters.money(
                      item.amount,
                      currencyCode: currency,
                      locale: locale,
                    ),
                    l10n.paymentMethodLabel(
                      item.paymentMethod.isEmpty ? 'other' : item.paymentMethod,
                    ),
                    l10n.paymentStatusLabel(item.paymentStatus),
                    '${item.attachments.length}',
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

  Future<Uint8List> buildPaymentsListPdf({
    required AppLocalizations l10n,
    required String projectName,
    required List<PaymentRecord> payments,
    required String currency,
    DateTime? startDate,
    DateTime? endDate,
    String? filterSummary,
  }) async {
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    final document = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd');
    final dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
    final locale = l10n.locale.languageCode;

    final total = sumPaymentAmounts(payments);
    final methodTotals = paymentMethodTotals(payments);

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

    pw.Widget dataTable(List<String> headers, List<List<String>> rows) {
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

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            l10n.t('exportPayments'),
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 22,
              color: PdfColor.fromHex('#F59E0B'),
            ),
          ),
          pw.SizedBox(height: 10),
          twoColumnTable([
            [l10n.t('project'), projectName.isEmpty ? '-' : projectName],
            if (startDate != null || endDate != null)
              [
                l10n.t('dateRange'),
                '${startDate != null ? dateFormat.format(startDate) : '...'} - ${endDate != null ? dateFormat.format(endDate) : '...'}',
              ],
            if (filterSummary != null && filterSummary.isNotEmpty)
              [l10n.t('filtersApplied'), filterSummary],
            [l10n.t('generated'), dateTimeFormat.format(DateTime.now())],
            [
              l10n.t('totalPayments'),
              Formatters.money(total, currencyCode: currency, locale: locale),
            ],
            [l10n.t('transactions'), '${payments.length}'],
          ]),
          sectionTitle(l10n.t('paymentBreakdown')),
          twoColumnTable(
            methodTotals.isEmpty
                ? [
                    [l10n.t('paymentMethod'), l10n.t('noDataYet')],
                  ]
                : methodTotals.entries
                      .map(
                        (entry) => [
                          l10n.paymentMethodLabel(entry.key),
                          Formatters.money(
                            entry.value,
                            currencyCode: currency,
                            locale: locale,
                          ),
                        ],
                      )
                      .toList(),
          ),
          sectionTitle(l10n.t('payments')),
          dataTable(
            [
              l10n.t('date'),
              l10n.t('entityName'),
              l10n.t('amount'),
              l10n.t('paymentMethod'),
              l10n.t('paymentStatus'),
              l10n.t('attachments'),
            ],
            payments
                .map(
                  (item) => [
                    dateFormat.format(item.date),
                    item.entityName,
                    Formatters.money(
                      item.amount,
                      currencyCode: currency,
                      locale: locale,
                    ),
                    l10n.paymentMethodLabel(
                      item.paymentMethod.isEmpty ? 'other' : item.paymentMethod,
                    ),
                    l10n.paymentStatusLabel(item.paymentStatus),
                    '${item.attachments.length}',
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
              [
                l10n.t('totalExpenses'),
                Formatters.money(
                  totalExpenses,
                  currencyCode: currency,
                  locale: locale,
                ),
              ],
              [
                l10n.t('totalPayments'),
                Formatters.money(
                  totalPayments,
                  currencyCode: currency,
                  locale: locale,
                ),
              ],
              [
                l10n.t('netProfit'),
                Formatters.money(
                  totalNet,
                  currencyCode: currency,
                  locale: locale,
                ),
              ],
              [l10n.t('topEntities'), filtered.length.toString()],
            ]),
            sectionTitle(l10n.t('entitySummary')),
            if (filtered.isEmpty)
              pw.Text(
                l10n.t('noDataYet'),
                style: pw.TextStyle(font: font, fontSize: 12),
              )
            else
              twoColumnTable(
                filtered
                    .map(
                      (entity) => [
                        entity.entityName,
                        Formatters.money(
                          entity.net,
                          currencyCode: currency,
                          locale: locale,
                        ),
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
            [
              l10n.t('laborSummary'),
              Formatters.money(
                insights.laborTotal,
                currencyCode: currency,
                locale: locale,
              ),
            ],
            [
              l10n.t('equipmentSummary'),
              Formatters.money(
                insights.equipmentTotal,
                currencyCode: currency,
                locale: locale,
              ),
            ],
          ]),
          sectionTitle(l10n.t('paymentBreakdown')),
          if (insights.paymentSummary.isEmpty)
            pw.Text(
              l10n.t('noDataYet'),
              style: pw.TextStyle(font: font, fontSize: 12),
            )
          else
            twoColumnTable(
              insights.paymentSummary.entries
                  .map(
                    (entry) => [
                      entry.key,
                      Formatters.money(
                        entry.value,
                        currencyCode: currency,
                        locale: locale,
                      ),
                    ],
                  )
                  .toList(),
            ),
          sectionTitle(l10n.t('recentTransactions')),
          if (insights.recentTransactions.isEmpty)
            pw.Text(
              l10n.t('noDataYet'),
              style: pw.TextStyle(font: font, fontSize: 12),
            )
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
            [
              l10n.t('totalIncome'),
              Formatters.money(
                metrics.totalIncome,
                currencyCode: currency,
                locale: locale,
              ),
            ],
            [
              l10n.t('totalExpenses'),
              Formatters.money(
                metrics.totalExpenses,
                currencyCode: currency,
                locale: locale,
              ),
            ],
            [
              l10n.t('netProfit'),
              Formatters.money(
                metrics.net,
                currencyCode: currency,
                locale: locale,
              ),
            ],
          ]),
          sectionTitle(l10n.t('weeklyInsights')),
          twoColumnTable([
            [l10n.t('topEntity'), insights.topEntity],
            [l10n.t('topCategory'), insights.topCategory],
            [
              l10n.t('laborSummary'),
              Formatters.money(
                insights.laborTotal,
                currencyCode: currency,
                locale: locale,
              ),
            ],
            [
              l10n.t('equipmentSummary'),
              Formatters.money(
                insights.equipmentTotal,
                currencyCode: currency,
                locale: locale,
              ),
            ],
          ]),
          sectionTitle(l10n.t('paymentBreakdown')),
          if (insights.paymentSummary.isEmpty)
            pw.Text(
              l10n.t('noDataYet'),
              style: pw.TextStyle(font: font, fontSize: 12),
            )
          else
            twoColumnTable(
              insights.paymentSummary.entries
                  .map(
                    (entry) => [
                      entry.key,
                      Formatters.money(
                        entry.value,
                        currencyCode: currency,
                        locale: locale,
                      ),
                    ],
                  )
                  .toList(),
            ),
          sectionTitle(l10n.t('recentTransactions')),
          if (insights.recentTransactions.isEmpty)
            pw.Text(
              l10n.t('noDataYet'),
              style: pw.TextStyle(font: font, fontSize: 12),
            )
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

  Future<Uint8List> buildCustomReportPdf({
    required AppLocalizations l10n,
    required Project project,
    required List<Expense> expenses,
    required List<PaymentRecord> payments,
    required DashboardWeeklyInsights insights,
    required List<EntitySummary> entitySummaries,
    required String currency,
    DateTime? startDate,
    DateTime? endDate,
    bool includeExpenses = true,
    bool includePayments = true,
    bool includeWeekly = true,
    bool includeEntities = true,
    bool includeDaily = true,
  }) async {
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    final document = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd');
    final dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
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

    final dateRangeLabel = (startDate != null || endDate != null)
        ? '${startDate != null ? dateFormat.format(startDate) : '...'} - ${endDate != null ? dateFormat.format(endDate) : '...'}'
        : null;

    final content = <pw.Widget>[
      pw.Text(
        l10n.t('buildCustomReport'),
        style: pw.TextStyle(
          font: fontBold,
          fontSize: 24,
          color: PdfColor.fromHex('#F59E0B'),
        ),
      ),
      pw.SizedBox(height: 12),
      twoColumnTable([
        [l10n.t('project'), project.name],
        [l10n.t('status'), l10n.projectStatusLabel(project.status)],
        if (dateRangeLabel != null) [l10n.t('dateRange'), dateRangeLabel],
        [l10n.t('generated'), dateTimeFormat.format(DateTime.now())],
      ]),
    ];

    if (includeExpenses) {
      final categoryTotals = expenseCategoryTotals(expenses);
      content.add(sectionTitle(l10n.t('exportExpenses')));
      content.add(
        twoColumnTable([
          [
            l10n.t('totalExpenses'),
            Formatters.money(
              sumExpenseAmounts(expenses),
              currencyCode: currency,
              locale: locale,
            ),
          ],
          [l10n.t('transactions'), '${expenses.length}'],
          ...categoryTotals.entries.map(
            (entry) => [
              l10n.expenseCategoryLabel(entry.key),
              Formatters.money(
                entry.value,
                currencyCode: currency,
                locale: locale,
              ),
            ],
          ),
        ]),
      );
      content.add(sectionTitle(l10n.t('expenseList')));
      content.add(
        twoColumnTable(
          expenses.isEmpty
              ? [
                  [l10n.t('expenses'), l10n.t('noDataYet')],
                ]
              : expenses
                    .map(
                      (expense) => [
                        '${dateFormat.format(expense.date)} ${l10n.expenseCategoryLabel(expense.category)}',
                        Formatters.money(
                          expense.amount,
                          currencyCode: currency,
                          locale: locale,
                        ),
                      ],
                    )
                    .toList(),
        ),
      );
    }

    if (includePayments) {
      final methodTotals = paymentMethodTotals(payments);
      content.add(sectionTitle(l10n.t('exportPayments')));
      content.add(
        twoColumnTable([
          [
            l10n.t('totalPayments'),
            Formatters.money(
              sumPaymentAmounts(payments),
              currencyCode: currency,
              locale: locale,
            ),
          ],
          [l10n.t('transactions'), '${payments.length}'],
          ...methodTotals.entries.map(
            (entry) => [
              l10n.paymentMethodLabel(entry.key),
              Formatters.money(
                entry.value,
                currencyCode: currency,
                locale: locale,
              ),
            ],
          ),
        ]),
      );
      content.add(sectionTitle(l10n.t('payments')));
      content.add(
        twoColumnTable(
          payments.isEmpty
              ? [
                  [l10n.t('payments'), l10n.t('noDataYet')],
                ]
              : payments
                    .map(
                      (payment) => [
                        '${dateFormat.format(payment.date)} ${l10n.paymentMethodLabel(payment.paymentMethod)}',
                        Formatters.money(
                          payment.amount,
                          currencyCode: currency,
                          locale: locale,
                        ),
                      ],
                    )
                    .toList(),
        ),
      );
    }

    if (includeWeekly) {
      content.add(sectionTitle(l10n.t('weeklyInsights')));
      content.add(
        twoColumnTable([
          [l10n.t('topEntity'), insights.topEntity],
          [l10n.t('topCategory'), insights.topCategory],
          [
            l10n.t('laborSummary'),
            Formatters.money(
              insights.laborTotal,
              currencyCode: currency,
              locale: locale,
            ),
          ],
          [
            l10n.t('equipmentSummary'),
            Formatters.money(
              insights.equipmentTotal,
              currencyCode: currency,
              locale: locale,
            ),
          ],
        ]),
      );
    }

    if (includeEntities) {
      content.add(sectionTitle(l10n.t('entitySummary')));
      content.add(
        twoColumnTable(
          entitySummaries.isEmpty
              ? [
                  [l10n.t('entitySummary'), l10n.t('noDataYet')],
                ]
              : entitySummaries
                    .map(
                      (summary) => [
                        '${summary.entityName} (${summary.entityType})',
                        Formatters.money(
                          summary.totalExpenses,
                          currencyCode: currency,
                          locale: locale,
                        ),
                      ],
                    )
                    .toList(),
        ),
      );
    }

    if (includeDaily) {
      final dailyRows = dailyExpenseBreakdown(expenses);
      content.add(sectionTitle(l10n.t('dailyBreakdown')));
      content.add(
        twoColumnTable(
          dailyRows.isEmpty
              ? [
                  [l10n.t('dailyBreakdown'), l10n.t('noDataYet')],
                ]
              : dailyRows
                    .map(
                      (row) => [
                        '${dateFormat.format(row.day)} - ${l10n.t('operationsCount', params: {'count': '${row.count}'})}',
                        Formatters.money(
                          row.total,
                          currencyCode: currency,
                          locale: locale,
                        ),
                      ],
                    )
                    .toList(),
        ),
      );
    }

    content.add(pw.SizedBox(height: 18));
    content.add(
      pw.Center(
        child: pw.Text(
          l10n.t('generatedByBuildozer'),
          style: pw.TextStyle(font: font, fontSize: 10),
        ),
      ),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => content,
      ),
    );

    return document.save();
  }

  Future<Uint8List> buildWorkerAccountingReportPdf({
    required AppLocalizations l10n,
    required String projectName,
    required List<WorkerAccountingRecord> records,
    required String currency,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _buildDomainAccountingReportPdf(
      l10n: l10n,
      title: l10n.t('workerAccounting'),
      projectName: projectName,
      rows: records
          .map(
            (record) => ReportAccountingRow(
              date: record.date,
              name: record.workerName,
              description: record.description,
              amount: record.amount,
              paymentMethod: record.paymentMethod,
              paymentStatus: record.paymentStatus,
              attachmentCount: record.attachments.length,
            ),
          )
          .toList(growable: false),
      currency: currency,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<Uint8List> buildContractorAccountingReportPdf({
    required AppLocalizations l10n,
    required String projectName,
    required List<ContractorAccountingRecord> records,
    required String currency,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _buildDomainAccountingReportPdf(
      l10n: l10n,
      title: l10n.t('contractorAccounting'),
      projectName: projectName,
      rows: records
          .map(
            (record) => ReportAccountingRow(
              date: record.date,
              name: record.contractorName,
              description: record.description,
              amount: record.amount,
              paymentMethod: record.paymentMethod,
              paymentStatus: record.paymentStatus,
              attachmentCount: record.attachments.length,
            ),
          )
          .toList(growable: false),
      currency: currency,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<Uint8List> buildEquipmentAccountingReportPdf({
    required AppLocalizations l10n,
    required String projectName,
    required List<EquipmentAccountingRecord> records,
    required String currency,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _buildDomainAccountingReportPdf(
      l10n: l10n,
      title: l10n.t('equipmentAccounting'),
      projectName: projectName,
      rows: records
          .map(
            (record) => ReportAccountingRow(
              date: record.date,
              name: record.providerName,
              description: record.description,
              amount: record.amount,
              paymentMethod: record.paymentMethod,
              paymentStatus: record.paymentStatus,
              attachmentCount: record.attachments.length,
            ),
          )
          .toList(growable: false),
      currency: currency,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<Uint8List> buildTransportAccountingReportPdf({
    required AppLocalizations l10n,
    required String projectName,
    required List<TransportProviderAccountingRecord> records,
    required String currency,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _buildDomainAccountingReportPdf(
      l10n: l10n,
      title: l10n.t('transportAccounting'),
      projectName: projectName,
      rows: records
          .map(
            (record) => ReportAccountingRow(
              date: record.date,
              name: record.providerName,
              description: record.description,
              amount: record.amount,
              paymentMethod: record.paymentMethod,
              paymentStatus: record.paymentStatus,
              attachmentCount: record.attachments.length,
            ),
          )
          .toList(growable: false),
      currency: currency,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<Uint8List> buildDailyReportPdf({
    required AppLocalizations l10n,
    required String projectName,
    required List<Expense> expenses,
    required String currency,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    final document = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd');
    final dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
    final locale = l10n.locale.languageCode;
    final dailyRows = dailyExpenseBreakdown(expenses);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            l10n.t('dailyBreakdown'),
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 24,
              color: PdfColor.fromHex('#F59E0B'),
            ),
          ),
          pw.SizedBox(height: 12),
          reportTwoColumnTable([
            [l10n.t('project'), projectName.isEmpty ? '-' : projectName],
            if (startDate != null || endDate != null)
              [
                l10n.t('dateRange'),
                '${startDate != null ? dateFormat.format(startDate) : '...'} - ${endDate != null ? dateFormat.format(endDate) : '...'}',
              ],
            [l10n.t('generated'), dateTimeFormat.format(DateTime.now())],
            [
              l10n.t('totalExpenses'),
              Formatters.money(
                sumExpenseAmounts(expenses),
                currencyCode: currency,
                locale: locale,
              ),
            ],
            [l10n.t('transactions'), '${expenses.length}'],
          ], font),
          reportSectionTitle(l10n.t('dailyBreakdown'), fontBold),
          reportTwoColumnTable(
            dailyRows.isEmpty
                ? [
                    [l10n.t('dailyBreakdown'), l10n.t('noDataYet')],
                  ]
                : dailyRows
                      .map(
                        (row) => [
                          '${dateFormat.format(row.day)} - ${l10n.t('operationsCount', params: {'count': '${row.count}'})}',
                          Formatters.money(
                            row.total,
                            currencyCode: currency,
                            locale: locale,
                          ),
                        ],
                      )
                      .toList(),
            font,
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

  Future<Uint8List> buildFilteredReportPdf({
    required AppLocalizations l10n,
    required Project project,
    required List<Expense> expenses,
    required List<PaymentRecord> payments,
    required DashboardWeeklyInsights insights,
    required List<EntitySummary> entitySummaries,
    required String currency,
    DateTime? startDate,
    DateTime? endDate,
    bool includeExpenses = true,
    bool includePayments = true,
    bool includeWeekly = true,
    bool includeEntities = true,
    bool includeDaily = true,
  }) {
    return buildCustomReportPdf(
      l10n: l10n,
      project: project,
      expenses: expenses,
      payments: payments,
      insights: insights,
      entitySummaries: entitySummaries,
      currency: currency,
      startDate: startDate,
      endDate: endDate,
      includeExpenses: includeExpenses,
      includePayments: includePayments,
      includeWeekly: includeWeekly,
      includeEntities: includeEntities,
      includeDaily: includeDaily,
    );
  }

  Future<Uint8List> _buildDomainAccountingReportPdf({
    required AppLocalizations l10n,
    required String title,
    required String projectName,
    required List<ReportAccountingRow> rows,
    required String currency,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    final document = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd');
    final dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
    final locale = l10n.locale.languageCode;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            title,
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 22,
              color: PdfColor.fromHex('#F59E0B'),
            ),
          ),
          pw.SizedBox(height: 10),
          reportTwoColumnTable([
            [l10n.t('project'), projectName.isEmpty ? '-' : projectName],
            if (startDate != null || endDate != null)
              [
                l10n.t('dateRange'),
                '${startDate != null ? dateFormat.format(startDate) : '...'} - ${endDate != null ? dateFormat.format(endDate) : '...'}',
              ],
            [l10n.t('generated'), dateTimeFormat.format(DateTime.now())],
            [
              l10n.t('totalExpenses'),
              Formatters.money(
                reportAccountingTotal(rows),
                currencyCode: currency,
                locale: locale,
              ),
            ],
            [l10n.t('transactions'), '${rows.length}'],
          ], font),
          reportSectionTitle(title, fontBold),
          if (rows.isEmpty)
            pw.Text(
              l10n.t('noDataYet'),
              style: pw.TextStyle(font: font, fontSize: 12),
            )
          else
            reportDataTable(
              headers: [
                l10n.t('date'),
                l10n.t('entityName'),
                l10n.t('description'),
                l10n.t('amount'),
                l10n.t('paymentMethod'),
                l10n.t('paymentStatus'),
                l10n.t('attachments'),
              ],
              rows: reportAccountingDataRows(
                l10n: l10n,
                rows: rows,
                currency: currency,
                locale: locale,
                dateFormat: dateFormat,
              ),
              font: font,
              fontBold: fontBold,
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
