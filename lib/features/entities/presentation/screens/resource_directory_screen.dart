import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/utils/number_parser.dart';
import 'package:buildtrack_app/core/utils/thousands_separator_input_formatter.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/app_search_field.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
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

extension _ResourceDirectoryActions on _ResourceDirectoryScreenState {
  Future<void> _showResourceForm({AppEntity? entity}) async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    if (workspaceId == null || workspaceId.isEmpty) {
      return;
    }
    final nameController = TextEditingController(text: entity?.name ?? '');
    final rateController = TextEditingController(
      text: entity?.defaultRate == null
          ? ''
          : ThousandsSeparatorInputFormatter.formatInitial(
              entity!.defaultRate!.toString(),
            ),
    );
    final unitController = TextEditingController(text: entity?.rateUnit ?? '');
    final phoneController = TextEditingController(
      text: entity?.phoneNumber ?? '',
    );
    final notesController = TextEditingController(text: entity?.notes ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entity == null ? l10n.t('add') : l10n.t('edit')),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: l10n.t('entityName')),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? l10n.t('fillRequiredFields')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: rateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [ThousandsSeparatorInputFormatter()],
                  decoration: InputDecoration(labelText: l10n.t('defaultRate')),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: unitController,
                  decoration: InputDecoration(labelText: l10n.t('rateUnit')),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: l10n.t('phoneNumber')),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: l10n.t('notes')),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState?.validate() != true) {
                return;
              }
              final repository = ref.read(entityRepositoryProvider);
              final rate = NumberParser.parseDouble(rateController.text);
              if (entity == null) {
                await repository.createEntity(
                  workspaceId: workspaceId,
                  name: nameController.text,
                  type: widget.type.entityType,
                  defaultRate: rate,
                  rateUnit: unitController.text,
                  phoneNumber: phoneController.text,
                  notes: notesController.text,
                );
              } else {
                await repository.updateEntity(
                  entityId: entity.id,
                  name: nameController.text,
                  type: widget.type.entityType,
                  defaultRate: rate,
                  rateUnit: unitController.text,
                  phoneNumber: phoneController.text,
                  notes: notesController.text,
                );
              }
              if (context.mounted) {
                Navigator.of(context).pop(true);
              }
            },
            child: Text(l10n.t('save')),
          ),
        ],
      ),
    );

    nameController.dispose();
    rateController.dispose();
    unitController.dispose();
    phoneController.dispose();
    notesController.dispose();
    if (saved == true) {
      await _loadInitial();
    }
  }

  Future<void> _confirmDelete(AppEntity entity) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('delete')),
        content: Text(
          l10n.t('deleteResourceConfirm', params: {'name': entity.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(entityRepositoryProvider).deleteEntity(entity.id);
    if (mounted) {
      await _loadInitial();
    }
  }
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
  Timer? _searchDebounce;
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
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        _loadInitial();
      }
    });
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
    final role = ref.watch(currentAccountingRoleProvider).value;
    final canAccessFinancial = role?.canAccessAccounting == true;
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final summaries = canAccessFinancial && workspaceId != null
        ? ref.watch(entityAggregationsProvider(workspaceId)).value
        : null;
    final summariesById = {
      for (final summary in summaries ?? const <EntitySummary>[])
        summary.entityId: summary,
    };

    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: Text(l10n.t(widget.type.titleKey)),
        actions: [
          TextButton.icon(
            key: const Key('qa_resource_add'),
            onPressed: () => _showResourceForm(),
            icon: Icon(Icons.add, color: t.accent),
            label: Text(
              l10n.t('add'),
              style: TextStyle(color: t.accent, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              AppSearchField(
                controller: _searchController,
                labelText: l10n.t('searchResources'),
                onChanged: _handleSearchChanged,
              ),
              const SizedBox(height: 16),
              if (!canAccessFinancial)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.t('projectFinancialAccessRestricted'),
                    style: TextStyle(fontSize: 12.5, color: t.textMuted),
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

    final t = context.tokens;
    return ListView.separated(
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          if (_isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return BuildButton(
            label: l10n.t('loadMore'),
            variant: BuildButtonVariant.outline,
            full: true,
            icon: Icons.expand_more,
            onPressed: _loadMore,
          );
        }
        final entity = _items[index];
        final summary = summariesById[entity.id];
        return BuildCard(
          onTap: () => _openEntity(entity),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(label: entity.name, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entity.name,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 4),
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
                      style: TextStyle(fontSize: 12.5, color: t.textMuted),
                    ),
                    if (canAccessFinancial && summary != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatTotals(l10n, summary),
                        style: TextStyle(fontSize: 12.5, color: t.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: Key('qa_resource_actions_${entity.id}'),
                icon: Icon(Icons.more_vert, color: t.textMuted),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _showResourceForm(entity: entity);
                    case 'delete':
                      _confirmDelete(entity);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'edit', child: Text(l10n.t('edit'))),
                  PopupMenuItem(value: 'delete', child: Text(l10n.t('delete'))),
                ],
              ),
            ],
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
