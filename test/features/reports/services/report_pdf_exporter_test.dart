import 'dart:convert';
import 'dart:ui';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/features/contractors/domain/contractor_accounting_record.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:buildtrack_app/features/reports/services/report_pdf_exporter.dart';
import 'package:buildtrack_app/features/workers/domain/worker_accounting_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = AppLocalizations(const Locale('en'));
  const project = Project(
    id: 'project_1',
    workspaceId: 'workspace_1',
    name: 'Tower A',
    clientName: 'Client One',
    contractValue: 10000,
    status: 'active',
    completionPercentage: 50,
    totalExpenses: 0,
    totalPayments: 0,
    netProfit: 0,
    isArchived: false,
  );

  test(
    'project report omits the revenue rows for a contract-less project',
    () async {
      const metrics = ReportMetrics(
        projectId: 'project_1',
        projectName: 'Tower A',
        status: 'active',
        isArchived: false,
        totalExpenses: 1500,
        totalIncome: 0,
        net: -1500,
        categoryTotals: {'materials': 1500},
        monthlyFlow: [],
        topWorkers: [],
        recentExpenses: [],
        recentPayments: [],
      );

      const exporter = ReportPdfExporter();
      final withContract = await exporter.buildProjectReportPdf(
        l10n: l10n,
        project: project,
        metrics: metrics,
        currency: 'EGP',
      );
      final contractLess = await exporter.buildProjectReportPdf(
        l10n: l10n,
        project: Project(
          id: project.id,
          workspaceId: project.workspaceId,
          name: project.name,
          clientName: project.clientName,
          contractValue: null,
          status: project.status,
          completionPercentage: project.completionPercentage,
          totalExpenses: project.totalExpenses,
          totalPayments: project.totalPayments,
          netProfit: project.netProfit,
          isArchived: project.isArchived,
        ),
        metrics: metrics,
        currency: 'EGP',
      );

      expect(ascii.decode(withContract.take(4).toList()), '%PDF');
      expect(ascii.decode(contractLess.take(4).toList()), '%PDF');

      // PDF bytes are compressed, so the rendered text cannot be asserted
      // directly — the established pattern in this suite is header + size.
      // Dropping the Total Income and Net Profit rows must make the
      // contract-less document strictly smaller; if the rows were still being
      // emitted, the two would be identical in length.
      expect(contractLess.length, lessThan(withContract.length));
    },
  );

  test(
    'custom report PDF generates with all accounting sections selected',
    () async {
      final bytes = await const ReportPdfExporter().buildCustomReportPdf(
        l10n: l10n,
        project: project,
        expenses: [
          Expense(
            id: 'expense_1',
            workspaceId: 'workspace_1',
            projectId: 'project_1',
            projectName: 'Tower A',
            category: 'materials',
            amount: 250,
            currency: 'EGP',
            date: DateTime.utc(2026, 6, 10),
            notes: 'Steel',
            supplierName: 'Supplier A',
            paymentMethod: 'cash',
            inputMethod: 'manual',
            transcript: '',
            source: '',
            storagePath: '',
            attachments: const [],
            isArchived: false,
          ),
        ],
        payments: [
          PaymentRecord(
            id: 'payment_1',
            workspaceId: 'workspace_1',
            projectId: 'project_1',
            amount: 500,
            date: DateTime.utc(2026, 6, 10),
            paymentMethod: 'bank',
            notes: 'Client payment',
            attachments: const [],
            isArchived: false,
          ),
        ],
        insights: DashboardWeeklyInsights(
          topEntity: 'Supplier A',
          topCategory: 'materials',
          laborTotal: 0,
          equipmentTotal: 0,
          paymentSummary: const {'bank': 500},
          recentTransactions: [
            WeeklyDashboardTransaction(
              title: 'Supplier A',
              amount: 250,
              date: DateTime.utc(2026, 6, 10),
              type: 'expense',
            ),
          ],
        ),
        entitySummaries: [
          EntitySummary(
            entityId: 'supplier_1',
            entityName: 'Supplier A',
            entityType: 'supplier',
            totalExpenses: 250,
            transactionCount: 1,
            categoryBreakdown: const {'materials': 250},
          ),
        ],
        currency: 'EGP',
        includeExpenses: true,
        includePayments: true,
        includeWeekly: true,
        includeEntities: true,
        includeDaily: true,
      );

      expect(ascii.decode(bytes.take(4).toList()), '%PDF');
      expect(bytes.length, greaterThan(1000));
    },
  );

  test('custom report PDF generates an empty-state document', () async {
    final bytes = await const ReportPdfExporter().buildCustomReportPdf(
      l10n: l10n,
      project: project,
      expenses: const [],
      payments: const [],
      insights: DashboardWeeklyInsights(
        topEntity: 'unassigned',
        topCategory: 'unassigned',
        laborTotal: 0,
        equipmentTotal: 0,
        paymentSummary: const {},
        recentTransactions: const [],
      ),
      entitySummaries: const [],
      currency: 'EGP',
      includeExpenses: false,
      includePayments: false,
      includeWeekly: false,
      includeEntities: false,
      includeDaily: false,
    );

    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(500));
  });

  test('worker and contractor accounting report PDFs generate', () async {
    final exporter = const ReportPdfExporter();
    final workerBytes = await exporter.buildWorkerAccountingReportPdf(
      l10n: l10n,
      projectName: 'Tower A',
      records: [
        WorkerAccountingRecord(
          id: 'worker_record_1',
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          workerId: 'worker_1',
          workerName: 'Sam',
          description: 'Wages',
          amount: 120,
          date: DateTime.utc(2026, 6, 10),
          paymentMethod: 'cash',
          paymentStatus: 'paid',
        ),
      ],
      currency: 'EGP',
    );
    final contractorBytes = await exporter.buildContractorAccountingReportPdf(
      l10n: l10n,
      projectName: 'Tower A',
      records: [
        ContractorAccountingRecord(
          id: 'contractor_record_1',
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          contractorId: 'contractor_1',
          contractorName: 'Mina Contracting',
          description: 'Concrete work',
          amount: 500,
          date: DateTime.utc(2026, 6, 10),
          paymentMethod: 'bank',
          paymentStatus: 'pending',
        ),
      ],
      currency: 'EGP',
    );

    expect(ascii.decode(workerBytes.take(4).toList()), '%PDF');
    expect(ascii.decode(contractorBytes.take(4).toList()), '%PDF');
    expect(workerBytes.length, greaterThan(1000));
    expect(contractorBytes.length, greaterThan(1000));
  });

  test('daily and filtered report PDFs generate', () async {
    final exporter = const ReportPdfExporter();
    final expenses = [
      Expense(
        id: 'expense_1',
        workspaceId: 'workspace_1',
        projectId: 'project_1',
        projectName: 'Tower A',
        category: 'materials',
        amount: 250,
        currency: 'EGP',
        date: DateTime.utc(2026, 6, 10),
        notes: 'Steel',
        supplierName: 'Supplier A',
        paymentMethod: 'cash',
        inputMethod: 'manual',
        transcript: '',
        source: '',
        storagePath: '',
        attachments: const [],
        isArchived: false,
      ),
    ];
    final payments = [
      PaymentRecord(
        id: 'payment_1',
        workspaceId: 'workspace_1',
        projectId: 'project_1',
        amount: 500,
        date: DateTime.utc(2026, 6, 10),
        paymentMethod: 'bank',
        notes: 'Client payment',
        attachments: const [],
        isArchived: false,
      ),
    ];
    final insights = DashboardWeeklyInsights(
      topEntity: 'Supplier A',
      topCategory: 'materials',
      laborTotal: 0,
      equipmentTotal: 0,
      paymentSummary: {'bank': 500},
      recentTransactions: [],
    );

    final dailyBytes = await exporter.buildDailyReportPdf(
      l10n: l10n,
      projectName: 'Tower A',
      expenses: expenses,
      currency: 'EGP',
    );
    final filteredBytes = await exporter.buildFilteredReportPdf(
      l10n: l10n,
      project: project,
      expenses: expenses,
      payments: payments,
      insights: insights,
      entitySummaries: const [],
      currency: 'EGP',
      startDate: DateTime.utc(2026, 6, 1),
      endDate: DateTime.utc(2026, 6, 30),
    );

    expect(ascii.decode(dailyBytes.take(4).toList()), '%PDF');
    expect(ascii.decode(filteredBytes.take(4).toList()), '%PDF');
    expect(dailyBytes.length, greaterThan(1000));
    expect(filteredBytes.length, greaterThan(1000));
  });
}
