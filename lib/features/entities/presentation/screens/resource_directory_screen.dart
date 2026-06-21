import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum ResourceDirectoryType {
  contractor(
    entityType: 'contractor',
    titleKey: 'contractorsDirectory',
    emptyKey: 'noContractorsYet',
  ),
  equipment(
    entityType: 'equipmentProvider',
    titleKey: 'equipmentDirectory',
    emptyKey: 'noEquipmentProvidersYet',
  ),
  transport(
    entityType: 'transportProvider',
    titleKey: 'transportDirectory',
    emptyKey: 'noTransportProvidersYet',
  );

  const ResourceDirectoryType({
    required this.entityType,
    required this.titleKey,
    required this.emptyKey,
  });

  final String entityType;
  final String titleKey;
  final String emptyKey;
}

class ResourceDirectoryScreen extends ConsumerStatefulWidget {
  const ResourceDirectoryScreen({required this.type, super.key});

  final ResourceDirectoryType type;

  @override
  ConsumerState<ResourceDirectoryScreen> createState() =>
      _ResourceDirectoryScreenState();
}

class _ResourceDirectoryScreenState
    extends ConsumerState<ResourceDirectoryScreen> {
  final _searchController = TextEditingController();
  final _items = <AppEntity>[];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadInitial);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    _cursor = null;
    _items.clear();
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _hasMore = false;
      _error = null;
    });
    await _load(reset: true);
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    await _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    if (workspaceId == null || workspaceId.isEmpty) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
      return;
    }
    try {
      final search = _searchController.text.trim();
      if (search.isNotEmpty) {
        final matches = await ref
            .read(entityRepositoryProvider)
            .searchEntities(
              workspaceId,
              search,
              type: widget.type.entityType,
              limit: 20,
            );
        if (!mounted) return;
        setState(() {
          _items
            ..clear()
            ..addAll(matches);
          _cursor = null;
          _hasMore = false;
          _isLoading = false;
          _isLoadingMore = false;
          _error = null;
        });
        return;
      }

      final page = await ref
          .read(entityRepositoryProvider)
          .fetchEntityDirectoryPage(
            workspaceId,
            type: widget.type.entityType,
            cursor: reset ? null : _cursor,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _error = error;
      });
    }
  }

  void _openEntity(AppEntity entity) {
    final path = switch (widget.type) {
      ResourceDirectoryType.contractor => AppRoutes.contractorsPath(
        entity.id,
        name: entity.name,
      ),
      ResourceDirectoryType.equipment => AppRoutes.equipmentPath(
        entity.id,
        name: entity.name,
      ),
      ResourceDirectoryType.transport => AppRoutes.transportProvidersPath(
        entity.id,
        name: entity.name,
      ),
    };
    context.push(path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final role = ref.watch(currentAccountingRoleProvider).valueOrNull;
    final canAccessFinancial = role?.canAccessAccounting == true;
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final summaries = canAccessFinancial && workspaceId != null
        ? ref.watch(entityAggregationsProvider(workspaceId)).valueOrNull
        : null;
    final summariesById = {
      for (final summary in summaries ?? const <EntitySummary>[])
        summary.entityId: summary,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t(widget.type.titleKey))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: l10n.t('searchResources'),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (_) => _loadInitial(),
              ),
              const SizedBox(height: 16),
              if (!canAccessFinancial)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.t('projectFinancialAccessRestricted'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.textBody),
                  ),
                ),
              if (!canAccessFinancial) const SizedBox(height: 8),
              Expanded(
                child: _buildList(
                  l10n,
                  canAccessFinancial: canAccessFinancial,
                  summariesById: summariesById,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    AppLocalizations l10n, {
    required bool canAccessFinancial,
    required Map<String, EntitySummary> summariesById,
  }) {
    if (_isLoading) return const AppLoadingSkeleton();
    final error = _error;
    if (error != null) {
      return AppRecoverableError(
        message: appErrorMessage(l10n, error),
        onRetry: _loadInitial,
      );
    }
    if (_items.isEmpty) {
      return AppEmptyState(message: l10n.t(widget.type.emptyKey));
    }

    return ListView.separated(
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return OutlinedButton.icon(
            onPressed: _isLoadingMore ? null : _loadMore,
            icon: _isLoadingMore
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more),
            label: Text(l10n.t('loadMore')),
          );
        }
        final entity = _items[index];
        final summary = summariesById[entity.id];
        return Card(
          child: ListTile(
            title: Text(entity.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t(
                    'lastUsedAtLabel',
                    params: {
                      'value':
                          entity.lastUsedAt
                              ?.toIso8601String()
                              .split('T')
                              .first ??
                          '-',
                    },
                  ),
                ),
                if (canAccessFinancial && summary != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formatTotals(l10n, summary),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.textBody),
                  ),
                ],
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openEntity(entity),
          ),
        );
      },
    );
  }

  String _formatTotals(AppLocalizations l10n, EntitySummary summary) {
    final locale = l10n.locale.languageCode;
    final expenses = Formatters.money(summary.totalExpenses, locale: locale);
    final income = Formatters.money(summary.totalPayments, locale: locale);
    final net = Formatters.money(summary.net, locale: locale);
    return [
      l10n.t('totalExpensesLabel', params: {'value': expenses}),
      l10n.t('totalIncomeLabel', params: {'value': income}),
      l10n.t('netLabel', params: {'value': net}),
    ].join(' · ');
  }
}
