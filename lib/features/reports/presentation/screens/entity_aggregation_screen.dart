import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/core/widgets/metric_card.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';
import 'package:buildtrack_app/features/reports/presentation/screens/entity_aggregation_detail_screen.dart';
import 'package:buildtrack_app/features/reports/services/report_pdf_exporter.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

typedef EntityAggregationPdfAction =
    Future<void> Function({
      required AppLocalizations l10n,
      required List<EntitySummary> summaries,
      required String selectedType,
      required String currency,
    });

class EntityAggregationScreen extends ConsumerStatefulWidget {
  const EntityAggregationScreen({this.onExportPdf, super.key});

  final EntityAggregationPdfAction? onExportPdf;

  @override
  ConsumerState<EntityAggregationScreen> createState() =>
      _EntityAggregationScreenState();
}

class _EntityAggregationScreenState
    extends ConsumerState<EntityAggregationScreen> {
  String _selectedType = 'all';
  String _searchText = '';

  Future<void> _exportEntitySummary({
    required AppLocalizations l10n,
    required List<EntitySummary> summaries,
    required String currency,
  }) async {
    try {
      final injectedExport = widget.onExportPdf;
      if (injectedExport != null) {
        await injectedExport(
          l10n: l10n,
          summaries: summaries,
          selectedType: _selectedType,
          currency: currency,
        );
      } else {
        final exporter = const ReportPdfExporter();
        final documentBytes = await exporter.buildEntitySummaryReportPdf(
          l10n: l10n,
          summaries: summaries,
          selectedType: _selectedType,
          currency: currency,
        );
        await Printing.layoutPdf(onLayout: (_) async => documentBytes);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(appErrorMessage(l10n, error))));
    }
  }

  static const _entityTypes = [
    'all',
    'supplier',
    'vendor',
    'worker',
    'contractor',
    'equipment',
    'transport',
    'other',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final hasWorkspace = workspaceId != null;
    final roleAsync = ref.watch(currentAccountingRoleProvider);
    final currentRole = roleAsync.valueOrNull;
    final canAccessReports =
        roleAsync.hasValue &&
        ref.watch(canAccessAccountingProvider(currentRole));
    final roleIsLoading = hasWorkspace && roleAsync.isLoading;
    final summariesAsync = workspaceId != null && canAccessReports
        ? ref.watch(entityAggregationsProvider(workspaceId))
        : const AsyncValue.data(<EntitySummary>[]);

    return AppBackScope(
      fallbackRoute: AppRoutes.dashboard,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.t('entitySummary')),
          leading: IconButton(
            icon: const BackButtonIcon(),
            onPressed: () =>
                appNavigateBack(context, fallbackRoute: AppRoutes.dashboard),
          ),
          actions: canAccessReports
              ? [
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    tooltip: l10n.t('exportPdf'),
                    onPressed: summariesAsync.when(
                      data: (summaries) => () async {
                        HapticFeedback.lightImpact();
                        final currency =
                            ref
                                .watch(currentUserSettingsProvider)
                                .valueOrNull
                                ?.defaultCurrency ??
                            'EGP';
                        await _exportEntitySummary(
                          l10n: l10n,
                          summaries: summaries,
                          currency: currency,
                        );
                      },
                      loading: () => null,
                      error: (error, stackTrace) => null,
                    ),
                  ),
                ]
              : const [],
        ),
        body: roleIsLoading
            ? const AppLoadingSkeleton(lineCount: 8)
            : hasWorkspace && !canAccessReports
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade400),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.t('reportAccessDenied'),
                            style: TextStyle(
                              color: Colors.red.shade400,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('entity_aggregation_search'),
                      decoration: InputDecoration(
                        labelText: l10n.t('search'),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchText = value.trim().toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    BelowDropdownField<String>(
                      label: l10n.t('entityType'),
                      value: _selectedType,
                      entries: _entityTypes
                          .map(
                            (type) => DropdownMenuEntry(
                              value: type,
                              label: type == 'all' ? l10n.t('allTypes') : type,
                            ),
                          )
                          .toList(),
                      onSelected: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedType = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: summariesAsync.whenStale(
                        data: (summaries) {
                          final filtered = summaries
                              .where((item) {
                                final matchesType =
                                    _selectedType == 'all' ||
                                    item.entityType == _selectedType;
                                final haystack =
                                    '${item.entityName} ${item.entityType}'
                                        .toLowerCase();
                                final matchesSearch =
                                    _searchText.isEmpty ||
                                    haystack.contains(_searchText);
                                return matchesType && matchesSearch;
                              })
                              .toList(growable: false);
                          if (filtered.isEmpty) {
                            return Center(child: Text(l10n.t('noDataYet')));
                          }
                          final totalExpenses = filtered.fold<double>(
                            0,
                            (sum, item) => sum + item.totalExpenses,
                          );
                          final totalPayments = filtered.fold<double>(
                            0,
                            (sum, item) => sum + item.totalPayments,
                          );
                          final totalNet = totalPayments - totalExpenses;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              GridView.count(
                                padding: EdgeInsets.zero,
                                crossAxisCount: 2,
                                shrinkWrap: true,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                physics: const NeverScrollableScrollPhysics(),
                                childAspectRatio: 2.2,
                                children: [
                                  MetricCard(
                                    label: l10n.t('totalExpenses'),
                                    value: totalExpenses.toStringAsFixed(2),
                                    color: Colors.red.shade400,
                                    icon: Icons.trending_down,
                                  ),
                                  MetricCard(
                                    label: l10n.t('totalPayments'),
                                    value: totalPayments.toStringAsFixed(2),
                                    color: Colors.green.shade600,
                                    icon: Icons.trending_up,
                                  ),
                                  MetricCard(
                                    label: l10n.t('netProfitLoss'),
                                    value: totalNet.toStringAsFixed(2),
                                    color: totalNet >= 0
                                        ? Colors.green.shade600
                                        : Colors.red.shade400,
                                    icon: Icons.account_balance_wallet_outlined,
                                  ),
                                  MetricCard(
                                    label: l10n.t('topEntities'),
                                    value: filtered.length.toString(),
                                    color: Colors.blue.shade600,
                                    icon: Icons.group,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final entity = filtered[index];
                                    return Card(
                                      child: ListTile(
                                        title: Text(entity.entityName),
                                        subtitle: Text(
                                          '${entity.entityType} • ${l10n.t('transactions')}: ${entity.transactionCount}',
                                        ),
                                        trailing: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '${l10n.t('netProfitLoss')}: ${entity.net.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              '${l10n.t('attachments')}: ${entity.attachmentCount}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  EntityAggregationDetailScreen(
                                                    summary: entity,
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                        loading: () => const AppLoadingSkeleton(lineCount: 8),
                        error: (error, _) =>
                            Center(child: Text(appErrorMessage(l10n, error))),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
