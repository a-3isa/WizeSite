import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/metric_card.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:flutter/material.dart';

class ProjectHeader extends StatelessWidget {
  const ProjectHeader({required this.project, super.key});
  final Project project;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isActive = project.status == 'active';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 16,
                          color: AppColors.textBody,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          project.clientName,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppColors.textBody,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.textBody.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive
                        ? AppColors.success.withValues(alpha: 0.2)
                        : AppColors.textBody.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  l10n.projectStatusLabel(project.status).toUpperCase(),
                  style: TextStyle(
                    color: isActive ? AppColors.success : AppColors.textBody,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _CompletionProgress(percentage: project.completionPercentage),
        ],
      ),
    );
  }
}

class _CompletionProgress extends StatelessWidget {
  const _CompletionProgress({required this.percentage});
  final double percentage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.t('completion'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            Text(
              '${percentage.toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.constructionOrange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage / 100,
            minHeight: 8,
            backgroundColor: AppColors.constructionOrange.withValues(
              alpha: 0.1,
            ),
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.constructionOrange,
            ),
          ),
        ),
      ],
    );
  }
}

class FinancialGrid extends StatelessWidget {
  const FinancialGrid({
    required this.project,
    required this.currency,
    super.key,
  });
  final Project project;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.4,
      children: [
        MetricCard(
          label: l10n.t('contractValue'),
          value: Formatters.money(
            project.contractValue,
            currencyCode: currency,
            locale: locale,
          ),
          color: AppColors.constructionOrange,
          icon: Icons.assignment_outlined,
        ),
        MetricCard(
          label: l10n.t('totalExpenses'),
          value: Formatters.money(
            project.totalExpenses,
            currencyCode: currency,
            locale: locale,
          ),
          color: AppColors.danger,
          icon: Icons.trending_down,
        ),
        MetricCard(
          label: l10n.t('totalIncome'),
          value: Formatters.money(
            project.totalPayments,
            currencyCode: currency,
            locale: locale,
          ),
          color: AppColors.success,
          icon: Icons.trending_up,
        ),
        MetricCard(
          label: l10n.t('netProfit'),
          value: Formatters.money(
            project.netProfit,
            currencyCode: currency,
            locale: locale,
          ),
          color: project.netProfit >= 0 ? AppColors.success : AppColors.danger,
          icon: Icons.account_balance_wallet_outlined,
        ),
      ],
    );
  }
}

class ActionGrid extends StatelessWidget {
  const ActionGrid({
    required this.onEdit,
    required this.onArchive,
    required this.onAddExpense,
    required this.onAddPayment,
    required this.onViewExpenses,
    required this.onViewPayments,
    required this.onAddWorkerEntry,
    required this.onViewWorkers,
    required this.onGenerateReport,
    required this.onDelete,
    super.key,
  });

  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onAddExpense;
  final VoidCallback onAddPayment;
  final VoidCallback onViewExpenses;
  final VoidCallback onViewPayments;
  final VoidCallback onAddWorkerEntry;
  final VoidCallback onViewWorkers;
  final VoidCallback onGenerateReport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('quickActions'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.2,
          children: [
            _ActionCard(
              qaKey: const Key('qa_project_add_expense'),
              icon: Icons.receipt_long_outlined,
              label: l10n.t('addExpense'),
              color: AppColors.danger,
              onTap: onAddExpense,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_add_payment'),
              icon: Icons.payments_outlined,
              label: l10n.t('addPayment'),
              color: AppColors.success,
              onTap: onAddPayment,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_add_worker_entry'),
              icon: Icons.engineering_outlined,
              label: l10n.t('addWorkerEntry'),
              color: AppColors.warning,
              onTap: onAddWorkerEntry,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_workers'),
              icon: Icons.engineering_outlined,
              label: l10n.t('workers'),
              color: AppColors.constructionOrange,
              onTap: onViewWorkers,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_report'),
              icon: Icons.picture_as_pdf_outlined,
              label: l10n.t('generateReport'),
              color: AppColors.constructionOrange,
              onTap: onGenerateReport,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_expenses'),
              icon: Icons.list_outlined,
              label: l10n.t('expenseList'),
              color: AppColors.textBody,
              onTap: onViewExpenses,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_payments'),
              icon: Icons.list_alt_outlined,
              label: l10n.t('paymentList'),
              color: AppColors.textBody,
              onTap: onViewPayments,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_edit'),
              icon: Icons.edit_outlined,
              label: l10n.t('edit'),
              color: AppColors.textBody,
              onTap: onEdit,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_archive'),
              icon: Icons.archive_outlined,
              label: l10n.t('archive'),
              color: AppColors.textBody,
              onTap: onArchive,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_delete'),
              icon: Icons.delete_outline,
              label: l10n.t('delete'),
              color: AppColors.danger,
              onTap: onDelete,
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    this.qaKey,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final Key? qaKey;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: qaKey,
      color: AppColors.surfaceSolid,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderGrey),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
