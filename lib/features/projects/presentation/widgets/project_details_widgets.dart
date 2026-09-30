import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/ds/animated_progress_bar.dart';
import 'package:buildtrack_app/core/widgets/ds/build_card.dart';
import 'package:buildtrack_app/core/widgets/metric_card.dart';
import 'package:buildtrack_app/core/widgets/section_header.dart';
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
        color: context.tokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.tokens.border),
        boxShadow: [
          BoxShadow(
            color: context.tokens.scrim.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
                            color: context.tokens.text,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 16,
                          color: context.tokens.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          project.clientName,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: context.tokens.textMuted,
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
                      ? context.tokens.income.withValues(alpha: 0.1)
                      : context.tokens.textMuted.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive
                        ? context.tokens.income.withValues(alpha: 0.2)
                        : context.tokens.textMuted.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  l10n.projectStatusLabel(project.status).toUpperCase(),
                  style: TextStyle(
                    color: isActive
                        ? context.tokens.income
                        : context.tokens.textMuted,
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
                color: context.tokens.text,
              ),
            ),
            Text(
              '${percentage.toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: context.tokens.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedProgressBar(
          value: percentage / 100,
          minHeight: 8,
          backgroundColor: context.tokens.accent.withValues(alpha: 0.1),
          color: context.tokens.accent,
        ),
      ],
    );
  }
}

/// Derived timeline indicator (days remaining / overdue / % of schedule
/// elapsed) for the project detail hero. Purely a presentation-layer
/// derivation from [Project.startDate] and [Project.expectedEndDate] — no
/// new schema. Renders nothing when either date is missing, rather than a
/// confusing "N/A" placeholder, since a partial date range can't produce a
/// meaningful duration.
class ProjectTimeline extends StatelessWidget {
  const ProjectTimeline({required this.project, super.key});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final start = project.startDate;
    final end = project.expectedEndDate;
    if (start == null || end == null) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final t = context.tokens;

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);

    final daysRemaining = endDate.difference(todayDate).inDays;
    final isComplete = project.status == 'completed';
    final overdue = daysRemaining < 0 && !isComplete;
    // Deliberately not budgetProgressColor()'s income/warning/expense scale:
    // the Timeline card sits directly above the budget-progress bar on the
    // project detail screen, so reusing t.warning here would make an
    // overdue-but-on-budget project look identical to a 70-90%-spent one.
    // Accent stays constant; overdue is conveyed via icon + weight instead.
    final statusColor = t.accent;

    final totalDays = endDate.difference(startDate).inDays;
    double? elapsedFraction;
    if (totalDays > 0) {
      final elapsedDays = todayDate.difference(startDate).inDays;
      elapsedFraction = (elapsedDays / totalDays).clamp(0.0, 1.0);
    }

    return BuildCard(
      key: const Key('qa_project_detail_timeline'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_outlined, size: 16, color: t.textMuted),
              const SizedBox(width: 6),
              Text(
                l10n.t('timeline'),
                style: TextStyle(fontWeight: FontWeight.w700, color: t.text),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (elapsedFraction != null) ...[
            AnimatedProgressBar(
              value: elapsedFraction,
              minHeight: 8,
              backgroundColor: t.surface3,
              color: statusColor,
            ),
            const SizedBox(height: 8),
          ],
          // Completed projects have no meaningful "days remaining"/"overdue"
          // concept — the timeline is done, whether it finished early or
          // late. Omit this line entirely rather than show a nonsensical
          // negative day count, mirroring the null-date graceful omission
          // above.
          if (!isComplete)
            Row(
              children: [
                Icon(
                  overdue ? Icons.event_busy : Icons.calendar_today_outlined,
                  size: 14,
                  color: statusColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    overdue
                        ? l10n.t(
                            'overdueByDays',
                            params: {'value': '${-daysRemaining}'},
                          )
                        : l10n.t(
                            'daysRemaining',
                            params: {'value': '$daysRemaining'},
                          ),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: overdue ? FontWeight.w900 : FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
                if (elapsedFraction != null && !overdue)
                  Text(
                    l10n.t(
                      'timelineElapsed',
                      params: {
                        'value': (elapsedFraction * 100).toStringAsFixed(0),
                      },
                    ),
                    style: TextStyle(fontSize: 11, color: t.textMuted),
                  ),
              ],
            ),
        ],
      ),
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

    // Contract, income and net all disappear together in expense-ledger mode,
    // leaving the expense card alone. A single child in a two-column grid
    // renders at half width with a dead column beside it, so the card is laid
    // out on its own instead (FR-012: removing a widget must leave no artefact).
    final cards = <Widget>[
      if (project.hasContractValue)
        MetricCard(
          label: l10n.t('contractValue'),
          value: Formatters.money(
            project.contractValue!,
            currencyCode: currency,
            locale: locale,
          ),
          color: context.tokens.accent,
          icon: Icons.assignment_outlined,
        ),
      MetricCard(
        label: l10n.t('totalExpenses'),
        value: Formatters.money(
          project.totalExpenses,
          currencyCode: currency,
          locale: locale,
        ),
        color: context.tokens.expense,
        icon: Icons.trending_down,
      ),
      if (!project.isExpenseLedger) ...[
        MetricCard(
          label: l10n.t('totalIncome'),
          value: Formatters.money(
            project.totalPayments,
            currencyCode: currency,
            locale: locale,
          ),
          color: context.tokens.income,
          icon: Icons.trending_up,
        ),
        MetricCard(
          label: l10n.t('netProfit'),
          value: Formatters.money(
            project.netProfit,
            currencyCode: currency,
            locale: locale,
          ),
          color: project.netProfit >= 0
              ? context.tokens.income
              : context.tokens.expense,
          icon: Icons.account_balance_wallet_outlined,
        ),
      ],
    ];

    if (cards.length == 1) {
      return SizedBox(
        key: const Key('qa_project_financial_grid_single'),
        child: cards.first,
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.4,
      children: cards,
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
    this.showPaymentActions = true,
    super.key,
  });

  /// False in expense-ledger mode, where the project cannot hold payments at
  /// all, so offering to add or view them would lead nowhere.
  final bool showPaymentActions;

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
        SectionHeader(title: l10n.t('quickActions')),
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
              color: context.tokens.expense,
              onTap: onAddExpense,
            ),
            if (showPaymentActions)
              _ActionCard(
                qaKey: const Key('qa_project_add_payment'),
                icon: Icons.payments_outlined,
                label: l10n.t('addPayment'),
                color: context.tokens.income,
                onTap: onAddPayment,
              ),
            _ActionCard(
              qaKey: const Key('qa_project_add_worker_entry'),
              icon: Icons.engineering_outlined,
              label: l10n.t('addWorkerEntry'),
              color: context.tokens.warning,
              onTap: onAddWorkerEntry,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_workers'),
              icon: Icons.engineering_outlined,
              label: l10n.t('workers'),
              color: context.tokens.accent,
              onTap: onViewWorkers,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_report'),
              icon: Icons.picture_as_pdf_outlined,
              label: l10n.t('generateReport'),
              color: context.tokens.accent,
              onTap: onGenerateReport,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_expenses'),
              icon: Icons.list_outlined,
              label: l10n.t('expenseList'),
              color: context.tokens.textMuted,
              onTap: onViewExpenses,
            ),
            if (showPaymentActions)
              _ActionCard(
                qaKey: const Key('qa_project_payments'),
                icon: Icons.list_alt_outlined,
                label: l10n.t('paymentList'),
                color: context.tokens.textMuted,
                onTap: onViewPayments,
              ),
            _ActionCard(
              qaKey: const Key('qa_project_edit'),
              icon: Icons.edit_outlined,
              label: l10n.t('edit'),
              color: context.tokens.textMuted,
              onTap: onEdit,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_archive'),
              icon: Icons.archive_outlined,
              label: l10n.t('archive'),
              color: context.tokens.textMuted,
              onTap: onArchive,
            ),
            _ActionCard(
              qaKey: const Key('qa_project_delete'),
              icon: Icons.delete_outline,
              label: l10n.t('delete'),
              color: context.tokens.expense,
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
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: context.tokens.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.tokens.border),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.78)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: context.tokens.onAccent, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.tokens.text,
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
