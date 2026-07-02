import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/app_search_field.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum _ActivityFilter { all, income, expense }

/// Workspace-wide recent activity: searchable, filterable list of the latest
/// income (payments) and expenses.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _searchController = TextEditingController();
  _ActivityFilter _filter = _ActivityFilter.all;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final locale = Localizations.localeOf(context).languageCode;
    final workspaceId = ref.watch(activeWorkspaceIdProvider) ?? '';
    final insightsAsync = workspaceId.isEmpty
        ? const AsyncValue<DashboardWeeklyInsights?>.data(null)
        : ref.watch(dashboardWeeklyInsightsProvider(workspaceId));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.t('activity'),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: t.text,
                ),
              ),
              const SizedBox(height: 14),
              AppSearchField(
                controller: _searchController,
                labelText: l10n.t('searchActivity'),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _chip(l10n.t('all'), _ActivityFilter.all),
                  const SizedBox(width: 8),
                  _chip(l10n.t('income'), _ActivityFilter.income),
                  const SizedBox(width: 8),
                  _chip(l10n.t('expenses'), _ActivityFilter.expense),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: insightsAsync.when(
                  loading: () => AppLoadingSkeleton(
                    semanticsLabel: l10n.t('loadingContent'),
                  ),
                  error: (_, _) => Center(
                    child: Text(
                      l10n.t('somethingWentWrong'),
                      style: TextStyle(color: t.textMuted),
                    ),
                  ),
                  data: (insights) {
                    final all = insights?.recentTransactions ??
                        const <WeeklyDashboardTransaction>[];
                    final rows = all.where((tx) {
                      final isIncome = tx.type == 'payment';
                      final matchesFilter = switch (_filter) {
                        _ActivityFilter.all => true,
                        _ActivityFilter.income => isIncome,
                        _ActivityFilter.expense => !isIncome,
                      };
                      final matchesQuery = _query.isEmpty ||
                          tx.title.toLowerCase().contains(_query);
                      return matchesFilter && matchesQuery;
                    }).toList();

                    if (rows.isEmpty) {
                      return Center(
                        child: Text(
                          l10n.t('noDataYet'),
                          style: TextStyle(color: t.textMuted),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final tx = rows[i];
                        final isIncome = tx.type == 'payment';
                        return BuildCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: MoneyRow(
                            title: tx.title,
                            subtitle: DateFormat.MMMd(locale).format(tx.date),
                            amount: NumberFormat.decimalPattern(locale)
                                .format(tx.amount.abs()),
                            kind: isIncome ? MoneyKind.income : MoneyKind.expense,
                            showDivider: false,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, _ActivityFilter value) {
    return BuildChip(
      label: label,
      active: _filter == value,
      onTap: () => setState(() => _filter = value),
    );
  }
}
