import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/accounting_entity_types.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/navigation/app_route_observer.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/active_filter_bar.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/app_search_field.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/data/expense_summary_providers.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/presentation/models/expense_group.dart';
import 'package:buildtrack_app/features/expenses/presentation/widgets/expense_group_section.dart';
import 'package:buildtrack_app/features/entities/presentation/widgets/entity_autocomplete_field.dart';
import 'package:buildtrack_app/features/common/presentation/controllers/transaction_bulk_archive_controller.dart';
import 'package:buildtrack_app/features/reports/services/report_document_actions.dart';
import 'package:buildtrack_app/features/reports/services/report_pdf_exporter.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({required this.projectId, super.key});

  final String projectId;

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen>
    with RouteAutoRefreshMixin<ExpensesScreen> {
  static const _pageSize = 20;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  ProviderSubscription<int>? _pendingSyncSubscription;
  ProviderSubscription<int>? _deadLetterSubscription;

  final List<Expense> _expenses = [];
  Object? _cursor;
  Object? _error;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _workspaceId;

  String? _categoryFilter;
  String? _paymentMethodFilter;
  String? _paymentStatusFilter;
  String? _supplierFilter;
  String? _entityFilterId;
  String _entityFilterName = '';
  String? _entityTypeFilter;
  DateTime? _startDateFilter;
  DateTime? _endDateFilter;
  ExpenseGroupMode _groupBy = ExpenseGroupMode.list;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _scrollController.addListener(_handleScroll);
    _pendingSyncSubscription = ref.listenManual<int>(
      offlinePendingCountProvider,
      (previous, next) {
        if (previous == null || previous == next) {
          return;
        }
        unawaited(_refreshIfCurrentRoute());
      },
    );
    _deadLetterSubscription = ref.listenManual<int>(
      offlineDeadLetterCountProvider,
      (previous, next) {
        if (previous == null || previous == next) {
          return;
        }
        unawaited(_refreshIfCurrentRoute());
      },
    );
  }

  @override
  void didUpdateWidget(covariant ExpensesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void dispose() {
    _pendingSyncSubscription?.close();
    _deadLetterSubscription?.close();
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _hasActiveExpenseFilters {
    return _categoryFilter != null ||
        _paymentMethodFilter != null ||
        _paymentStatusFilter != null ||
        _supplierFilter != null ||
        _entityFilterId != null ||
        _entityFilterName.isNotEmpty ||
        _entityTypeFilter != null ||
        _searchController.text.trim().isNotEmpty ||
        _startDateFilter != null ||
        _endDateFilter != null;
  }

  void _clearExpenseFilters() {
    setState(() {
      _categoryFilter = null;
      _paymentMethodFilter = null;
      _paymentStatusFilter = null;
      _supplierFilter = null;
      _entityFilterId = null;
      _entityFilterName = '';
      _entityTypeFilter = null;
      _startDateFilter = null;
      _endDateFilter = null;
      _searchController.clear();
    });
  }

  /// Removes only the named filter, leaving the others applied.
  void _removeExpenseFilter(String id) {
    setState(() {
      switch (id) {
        case 'category':
          _categoryFilter = null;
        case 'method':
          _paymentMethodFilter = null;
        case 'status':
          _paymentStatusFilter = null;
        case 'supplier':
          _supplierFilter = null;
        case 'entity':
          _entityFilterId = null;
          _entityFilterName = '';
        case 'entityType':
          _entityTypeFilter = null;
        case 'date':
          _startDateFilter = null;
          _endDateFilter = null;
        case 'search':
          _searchController.clear();
      }
    });
  }

  List<ActiveFilter> _activeExpenseFilters(AppLocalizations l10n) {
    final filters = <ActiveFilter>[];
    if (_categoryFilter != null) {
      filters.add(
        ActiveFilter(
          id: 'category',
          label: l10n.expenseCategoryLabel(_categoryFilter!),
        ),
      );
    }
    if (_paymentMethodFilter != null) {
      filters.add(
        ActiveFilter(
          id: 'method',
          label: l10n.paymentMethodLabel(_paymentMethodFilter!),
        ),
      );
    }
    if (_paymentStatusFilter != null) {
      filters.add(
        ActiveFilter(
          id: 'status',
          label: l10n.paymentStatusLabel(_paymentStatusFilter!),
        ),
      );
    }
    if (_supplierFilter != null) {
      filters.add(
        ActiveFilter(
          id: 'supplier',
          label: '${l10n.t('supplierName')}: $_supplierFilter',
        ),
      );
    }
    if (_entityFilterId != null) {
      filters.add(
        ActiveFilter(
          id: 'entity',
          label: _entityFilterName.isNotEmpty
              ? '${l10n.t('entityName')}: $_entityFilterName'
              : l10n.t('entitySummary'),
        ),
      );
    }
    if (_entityTypeFilter != null) {
      filters.add(
        ActiveFilter(
          id: 'entityType',
          label: _entityTypeLabel(l10n, _entityTypeFilter!),
        ),
      );
    }
    if (_startDateFilter != null || _endDateFilter != null) {
      filters.add(
        ActiveFilter(
          id: 'date',
          label:
              '${_startDateFilter?.toIso8601String().split('T').first ?? l10n.t('anyDate')} – ${_endDateFilter?.toIso8601String().split('T').first ?? l10n.t('anyDate')}',
        ),
      );
    }
    if (_searchController.text.trim().isNotEmpty) {
      filters.add(
        ActiveFilter(
          id: 'search',
          label: l10n.t(
            'searchFilterLabel',
            params: {'query': _searchController.text.trim()},
          ),
        ),
      );
    }
    return filters;
  }

  Future<void> _openExpenseFilterSheet() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: MediaQuery.of(context).viewInsets,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Filters',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    BelowDropdownField<String>(
                      label: l10n.t('category'),
                      value: _categoryFilter ?? '',
                      entries: [
                        DropdownMenuEntry(value: '', label: l10n.t('all')),
                        DropdownMenuEntry(
                          value: 'materials',
                          label: l10n.expenseCategoryLabel('materials'),
                        ),
                        DropdownMenuEntry(
                          value: 'equipment',
                          label: l10n.expenseCategoryLabel('equipment'),
                        ),
                        DropdownMenuEntry(
                          value: 'transport',
                          label: l10n.expenseCategoryLabel('transport'),
                        ),
                        DropdownMenuEntry(
                          value: 'other',
                          label: l10n.expenseCategoryLabel('other'),
                        ),
                      ],
                      onSelected: (value) => setModalState(() {
                        _categoryFilter = value?.isEmpty == true ? null : value;
                      }),
                    ),
                    const SizedBox(height: 12),
                    BelowDropdownField<String>(
                      label: l10n.t('paymentMethod'),
                      value: _paymentMethodFilter ?? '',
                      entries: [
                        DropdownMenuEntry(value: '', label: l10n.t('all')),
                        DropdownMenuEntry(
                          value: 'cash',
                          label: l10n.paymentMethodLabel('cash'),
                        ),
                        DropdownMenuEntry(
                          value: 'bank',
                          label: l10n.paymentMethodLabel('bank'),
                        ),
                        DropdownMenuEntry(
                          value: 'check',
                          label: l10n.paymentMethodLabel('check'),
                        ),
                      ],
                      onSelected: (value) => setModalState(() {
                        _paymentMethodFilter = value?.isEmpty == true
                            ? null
                            : value;
                      }),
                    ),
                    const SizedBox(height: 12),
                    BelowDropdownField<String>(
                      label: l10n.t('paymentStatus'),
                      value: _paymentStatusFilter ?? '',
                      entries: [
                        DropdownMenuEntry(value: '', label: l10n.t('all')),
                        for (final status in PaymentStatuses.values)
                          DropdownMenuEntry(
                            value: status,
                            label: l10n.paymentStatusLabel(status),
                          ),
                      ],
                      onSelected: (value) => setModalState(() {
                        _paymentStatusFilter = value?.isEmpty == true
                            ? null
                            : value;
                      }),
                    ),
                    const SizedBox(height: 12),
                    BelowDropdownField<String>(
                      label: l10n.t('entityType'),
                      value: _entityTypeFilter ?? '',
                      entries: [
                        DropdownMenuEntry(value: '', label: l10n.t('allTypes')),
                        for (final type in AccountingEntityTypes.values)
                          DropdownMenuEntry(
                            value: type,
                            label: _entityTypeLabel(l10n, type),
                          ),
                      ],
                      onSelected: (value) => setModalState(() {
                        _entityTypeFilter = value?.isEmpty == true
                            ? null
                            : value;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: l10n.t('supplierNameOptional'),
                        hintText: l10n.t('supplierNameOptional'),
                      ),
                      initialValue: _supplierFilter,
                      onChanged: (value) => setModalState(() {
                        _supplierFilter = value.trim().isEmpty
                            ? null
                            : value.trim();
                      }),
                    ),
                    const SizedBox(height: 12),
                    if (workspaceId != null && workspaceId.isNotEmpty)
                      EntityAutocompleteField(
                        workspaceId: workspaceId,
                        label: l10n.t('entityNameOptional'),
                        initialEntityId: _entityFilterId,
                        initialEntityName: _entityFilterName.isNotEmpty
                            ? _entityFilterName
                            : null,
                        onChanged: (entityId, entityName) {
                          setModalState(() {
                            _entityFilterId = entityId;
                            _entityFilterName = entityName ?? '';
                          });
                        },
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final initialDate =
                                  _startDateFilter ??
                                  DateTime.now().subtract(
                                    const Duration(days: 30),
                                  );
                              final picked = await showDatePicker(
                                context: context,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                                initialDate: initialDate,
                              );
                              if (picked == null) {
                                return;
                              }
                              setModalState(() {
                                _startDateFilter = picked;
                              });
                            },
                            child: Text(
                              _startDateFilter == null
                                  ? l10n.t('startDate')
                                  : _startDateFilter!
                                        .toIso8601String()
                                        .split('T')
                                        .first,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final initialDate =
                                  _endDateFilter ?? DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                                initialDate: initialDate,
                              );
                              if (picked == null) {
                                return;
                              }
                              setModalState(() {
                                _endDateFilter = picked;
                              });
                            },
                            child: Text(
                              _endDateFilter == null
                                  ? l10n.t('endDate')
                                  : _endDateFilter!
                                        .toIso8601String()
                                        .split('T')
                                        .first,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() {
                              _clearExpenseFilters();
                              Navigator.of(context).pop();
                            }),
                            child: Text(l10n.t('clearFilters')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(l10n.t('apply')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (mounted) {
      setState(() {});
      await _refresh();
    }
  }

  @override
  Future<void> onScreenVisible() async {
    if (!mounted) {
      return;
    }
    await _refresh();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoadingInitial ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    if (_scrollController.position.extentAfter < 320) {
      _loadMore();
    }
  }

  Future<void> _refresh() async {
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    _workspaceId = workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _expenses.clear();
        _cursor = null;
        _error = null;
        _hasMore = false;
        _isLoadingInitial = false;
        _isLoadingMore = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _expenses.clear();
        _cursor = null;
        _error = null;
        _hasMore = true;
        _isLoadingInitial = true;
        _isLoadingMore = false;
      });
    }

    await _loadMore(reset: true);
  }

  Future<void> _refreshIfCurrentRoute() async {
    if (!mounted) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true) {
      return;
    }
    await _refresh();
  }

  Future<void> _loadMore({bool reset = false}) async {
    final workspaceId = _workspaceId ?? ref.read(activeWorkspaceIdProvider);
    if (workspaceId == null || workspaceId.isEmpty) {
      return;
    }
    if (!reset && (_isLoadingInitial || _isLoadingMore || !_hasMore)) {
      return;
    }

    if (mounted) {
      setState(() {
        _error = null;
        if (reset) {
          _isLoadingInitial = true;
          _isLoadingMore = false;
        } else {
          _isLoadingMore = true;
        }
      });
    }

    try {
      final page = await ref
          .read(expenseRepositoryProvider)
          .fetchExpensesPage(
            workspaceId,
            projectId: widget.projectId,
            entityId: _entityFilterId,
            entityName: _entityFilterName,
            entityType: _entityTypeFilter,
            category: _categoryFilter,
            paymentMethod: _paymentMethodFilter,
            paymentStatus: _paymentStatusFilter,
            searchText: _searchController.text.trim(),
            startDate: _startDateFilter,
            endDate: _endDateFilter,
            cursor: reset ? null : _cursor,
            pageSize: _pageSize,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _expenses
            ..clear()
            ..addAll(page.items);
        } else {
          _expenses.addAll(page.items);
        }
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _error = null;
        _isLoadingInitial = false;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoadingInitial = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _duplicateLastExpense() async {
    if (_expenses.isEmpty) {
      return;
    }
    await context.push(
      AppRoutes.addExpensePath(projectId: widget.projectId),
      extra: _expenses.first,
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _openAddExpense() async {
    await context.push(
      AppRoutes.addExpensePath(projectId: widget.projectId),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _openEditExpense(Expense expense) async {
    await context.push(
      AppRoutes.expenseEditPath(expense.id, projectId: widget.projectId),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _archiveExpense(
    BuildContext context,
    AppLocalizations l10n,
    Expense expense,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('archive')),
        content: Text(l10n.t('confirmArchiveExpense')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.t('archive')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final result = await ref
        .read(expenseRepositoryProvider)
        .archiveExpense(expense.id);
    if (!mounted) {
      return;
    }

    setState(() {
      _expenses.removeWhere((item) => item.id == expense.id);
    });

    if (result.queued) {
      await ref.read(offlineQueueCoordinatorProvider).refreshCounts();
      unawaited(ref.read(offlineQueueCoordinatorProvider).drainNow());
      if (!mounted) {
        return;
      }
      pushAppUiNotice(ref, l10n.t('queuedForSync'));
    }
  }

  Future<void> _archiveSelectedExpenses(AppLocalizations l10n) async {
    final controller = ref.read(
      transactionBulkArchiveControllerProvider.notifier,
    );
    final result = await controller.archiveSelected(
      archiveOne: ref.read(expenseRepositoryProvider).archiveExpense,
      confirm: (selectedCount) async {
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                content: Text(
                  l10n.t(
                    'bulkArchiveConfirm',
                    params: {'count': '$selectedCount'},
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l10n.t('cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(l10n.t('archive')),
                  ),
                ],
              ),
            ) ??
            false;
      },
    );
    if (!mounted || result == null || result.cancelled) return;
    setState(() {
      _expenses.removeWhere((item) => result.succeeded.contains(item.id));
    });
    if (result.queued) {
      await ref.read(offlineQueueCoordinatorProvider).refreshCounts();
      unawaited(ref.read(offlineQueueCoordinatorProvider).drainNow());
    }
    if (result.failed.isNotEmpty) {
      pushAppUiNotice(ref, l10n.t('bulkArchivePartialFailure'));
    } else if (result.queued) {
      pushAppUiNotice(ref, l10n.t('queuedForSync'));
    }
  }

  List<Expense> _filteredExpenses() {
    final search = _searchController.text.trim().toLowerCase();
    return _expenses
        .where((expense) {
          if (_categoryFilter != null && expense.category != _categoryFilter) {
            return false;
          }
          if (_paymentMethodFilter != null &&
              expense.paymentMethod.toLowerCase() != _paymentMethodFilter) {
            return false;
          }
          if (_paymentStatusFilter != null &&
              expense.paymentStatus.toLowerCase() != _paymentStatusFilter) {
            return false;
          }
          if (_entityTypeFilter != null &&
              expense.entityType != _entityTypeFilter) {
            return false;
          }
          if (_supplierFilter != null &&
              !expense.supplierName.toLowerCase().contains(
                _supplierFilter!.toLowerCase(),
              ) &&
              !expense.notes.toLowerCase().contains(
                _supplierFilter!.toLowerCase(),
              )) {
            return false;
          }
          if (_entityFilterId != null && expense.entityId != _entityFilterId) {
            return false;
          }
          if (_entityFilterId == null && _entityFilterName.isNotEmpty) {
            final entityName = _entityFilterName.toLowerCase();
            if (expense.entityName.toLowerCase() != entityName &&
                expense.supplierName.toLowerCase() != entityName) {
              return false;
            }
          }
          if (_startDateFilter != null &&
              expense.date.isBefore(_startDateFilter!)) {
            return false;
          }
          if (_endDateFilter != null && expense.date.isAfter(_endDateFilter!)) {
            return false;
          }
          if (search.isNotEmpty) {
            final haystack =
                '${expense.projectName} ${expense.category} ${expense.notes} ${expense.supplierName} ${expense.paymentMethod} ${expense.entityName}'
                    .toLowerCase();
            if (!haystack.contains(search)) {
              return false;
            }
          }
          return true;
        })
        .toList(growable: false);
  }

  Future<void> _exportPdf({required bool share}) async {
    final l10n = AppLocalizations.of(context);
    final expenses = _filteredExpenses();
    if (expenses.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.t('noDataYet'))));
      return;
    }
    final currency =
        ref.read(currentUserSettingsProvider).value?.defaultCurrency ?? 'EGP';
    final filterParts = <String>[];
    if (_categoryFilter != null) {
      filterParts.add(l10n.expenseCategoryLabel(_categoryFilter!));
    }
    if (_paymentMethodFilter != null) {
      filterParts.add(l10n.paymentMethodLabel(_paymentMethodFilter!));
    }
    if (_paymentStatusFilter != null) {
      filterParts.add(l10n.paymentStatusLabel(_paymentStatusFilter!));
    }
    if (_entityFilterName.isNotEmpty) {
      filterParts.add(_entityFilterName);
    }
    final search = _searchController.text.trim();
    if (search.isNotEmpty) {
      filterParts.add(search);
    }
    try {
      final bytes = await const ReportPdfExporter().buildExpensesListPdf(
        l10n: l10n,
        projectName: expenses.first.projectName,
        expenses: expenses,
        currency: currency,
        startDate: _startDateFilter,
        endDate: _endDateFilter,
        filterSummary: filterParts.isEmpty ? null : filterParts.join(', '),
      );
      final actions = ReportDocumentActions();
      final result = share
          ? await actions.shareDocument(bytes: bytes, filename: 'expenses.pdf')
          : await actions.printDocument(
              bytes: bytes,
              name: l10n.t('expenseList'),
            );
      if (result.isFailed && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(appErrorMessage(l10n, result.error))),
          );
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filtered = _filteredExpenses();
    final bulkState = ref.watch(transactionBulkArchiveControllerProvider);
    final bulkController = ref.read(
      transactionBulkArchiveControllerProvider.notifier,
    );
    final locale = Localizations.localeOf(context).languageCode;
    final currency =
        ref.watch(currentUserSettingsProvider).value?.defaultCurrency ?? 'EGP';
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final today = DateTime.now();
    final summaryScope = workspaceId == null || workspaceId.isEmpty
        ? null
        : ExpenseSummaryScope(
            workspaceId: workspaceId,
            projectId: widget.projectId,
            now: DateTime(today.year, today.month, today.day),
          );
    final summaryAsync = summaryScope == null
        ? const AsyncValue<ExpenseQuickSummary>.data(ExpenseQuickSummary())
        : ref.watch(expenseQuickSummaryProvider(summaryScope));

    return AppBackScope(
      fallbackRoute: AppRoutes.projectDetailPath(widget.projectId),
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('expenseList'),
          fallbackRoute: AppRoutes.projectDetailPath(widget.projectId),
          actions: bulkState.isSelecting
              ? [
                  IconButton(
                    tooltip: l10n.t('selectionMode'),
                    onPressed: bulkState.isInProgress
                        ? null
                        : () => bulkController.selectAll(
                            filtered.map((expense) => expense.id),
                          ),
                    icon: const Icon(Icons.select_all),
                  ),
                  IconButton(
                    tooltip: l10n.t('archiveSelected'),
                    onPressed: bulkState.isInProgress
                        ? null
                        : () => _archiveSelectedExpenses(l10n),
                    icon: bulkState.isInProgress
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.archive_outlined),
                  ),
                  IconButton(
                    tooltip: l10n.t('cancel'),
                    onPressed: bulkState.isInProgress
                        ? null
                        : bulkController.clear,
                    icon: const Icon(Icons.close),
                  ),
                ]
              : [
                  PopupMenuButton<String>(
                    tooltip: l10n.t('exportPdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    onSelected: (value) => _exportPdf(share: value == 'share'),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'print',
                        child: Row(
                          children: [
                            const Icon(Icons.print_outlined, size: 20),
                            const SizedBox(width: 12),
                            Text(l10n.t('printReport')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: Row(
                          children: [
                            const Icon(Icons.ios_share, size: 20),
                            const SizedBox(width: 12),
                            Text(l10n.t('shareReport')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
        ),
        floatingActionButton: bulkState.isSelecting
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_expenses.isNotEmpty) ...[
                    FloatingActionButton.extended(
                      heroTag: 'duplicate_last_expense',
                      onPressed: _duplicateLastExpense,
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(l10n.t('duplicateLastExpense')),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FloatingActionButton.extended(
                    onPressed: _openAddExpense,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.t('addExpense')),
                  ),
                ],
              ),
        body: Column(
          children: [
            summaryAsync.whenStale(
              data: (summary) => _ExpenseSummaryCards(
                summary: summary,
                locale: locale,
                currency: currency,
                l10n: l10n,
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: AppRecoverableError(
                  message: appErrorMessage(l10n, error),
                ),
              ),
              loading: () => const LinearProgressIndicator(minHeight: 2),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: AppSearchField(
                controller: _searchController,
                labelText: l10n.t('search'),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openExpenseFilterSheet,
                  icon: const Icon(Icons.filter_list),
                  label: Text(l10n.t('filters')),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
              child: BelowDropdownField<String>(
                label: l10n.t('groupBy'),
                value: _groupBy.name,
                entries: [
                  DropdownMenuEntry(
                    value: ExpenseGroupMode.list.name,
                    label: l10n.t('ungroup'),
                  ),
                  DropdownMenuEntry(
                    value: ExpenseGroupMode.date.name,
                    label: l10n.t('groupByDate'),
                  ),
                  DropdownMenuEntry(
                    value: ExpenseGroupMode.relativeDate.name,
                    label: l10n.t('groupByRelativeDate'),
                  ),
                  DropdownMenuEntry(
                    value: ExpenseGroupMode.category.name,
                    label: l10n.t('groupByCategory'),
                  ),
                  DropdownMenuEntry(
                    value: ExpenseGroupMode.entity.name,
                    label: l10n.t('groupByEntity'),
                  ),
                  DropdownMenuEntry(
                    value: ExpenseGroupMode.paymentMethod.name,
                    label: l10n.t('groupByPaymentMethod'),
                  ),
                ],
                onSelected: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _groupBy = ExpenseGroupMode.values.firstWhere(
                      (element) => element.name == value,
                      orElse: () => ExpenseGroupMode.list,
                    );
                  });
                },
              ),
            ),
            if (_hasActiveExpenseFilters)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: ActiveFilterBar(
                  filters: _activeExpenseFilters(l10n),
                  onRemove: _removeExpenseFilter,
                  onClearAll: _clearExpenseFilters,
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: _buildContent(context, l10n, filtered, locale),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n,
    List<Expense> filtered,
    String locale,
  ) {
    if (_groupBy != ExpenseGroupMode.list) {
      return _buildGroupedContent(context, l10n, filtered, locale);
    }
    if (_isLoadingInitial && _expenses.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 24),
          AppLoadingSkeleton(lineCount: 6),
        ],
      );
    }

    if (_error != null && _expenses.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 24),
            child: AppRecoverableError(
              message: appErrorMessage(l10n, _error),
              onRetry: _refresh,
            ),
          ),
        ],
      );
    }

    if (filtered.isEmpty) {
      final filtersActive = _hasActiveExpenseFilters;
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 24),
            child: filtersActive
                ? AppEmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    message: l10n.t('noFilterResults'),
                    actionLabel: l10n.t('clearFilters'),
                    onAction: _clearExpenseFilters,
                  )
                : AppEmptyState(
                    icon: Icons.receipt_long_outlined,
                    message: l10n.t('noExpensesYet'),
                    actionLabel: l10n.t('addExpense'),
                    onAction: _openAddExpense,
                  ),
          ),
        ],
      );
    }

    final itemCount = filtered.length + (_isLoadingMore ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 4),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= filtered.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _expenseCard(context, l10n, filtered[index], locale),
        );
      },
    );
  }

  Widget _buildGroupedContent(
    BuildContext context,
    AppLocalizations l10n,
    List<Expense> filtered,
    String locale,
  ) {
    if (filtered.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              _expenses.isEmpty
                  ? l10n.t('noExpensesYet')
                  : l10n.t('noFilterResults'),
            ),
          ),
        ],
      );
    }

    final groups = groupExpenses(filtered, _groupBy);

    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 4),
      children: groups.map((group) {
        return ExpenseGroupSection(
          group: _localizedGroup(group, l10n),
          itemBuilder: (context, expense) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _expenseCard(context, l10n, expense, locale),
          ),
        );
      }).toList(),
    );
  }

  Widget _expenseCard(
    BuildContext context,
    AppLocalizations l10n,
    Expense expense,
    String locale,
  ) {
    final bulkState = ref.watch(transactionBulkArchiveControllerProvider);
    final bulkController = ref.read(
      transactionBulkArchiveControllerProvider.notifier,
    );
    final selected = bulkState.isSelected(expense.id);
    final projectLabel = expense.projectName.isEmpty
        ? expense.projectId
        : expense.projectName;
    return Card(
      child: ListTile(
        selected: selected,
        leading: bulkState.isSelecting
            ? Checkbox(
                value: selected,
                onChanged: bulkState.isInProgress
                    ? null
                    : (_) => bulkController.toggle(expense.id),
              )
            : null,
        onLongPress: bulkState.isInProgress
            ? null
            : () => bulkController.toggle(expense.id),
        onTap: () {
          if (bulkState.isSelecting) {
            if (!bulkState.isInProgress) {
              bulkController.toggle(expense.id);
            }
            return;
          }
          context.push(
            AppRoutes.expenseDetailPath(
              expense.id,
              projectId: widget.projectId,
            ),
          );
        },
        title: Text(
          '${Formatters.money(expense.amount, currencyCode: expense.currency, locale: locale)} | ${l10n.expenseCategoryLabel(expense.category)}',
        ),
        subtitle: Text(_expenseSubtitle(expense, projectLabel, l10n)),
        trailing: bulkState.isSelecting
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (expense.attachments.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.attach_file, size: 20),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await _openEditExpense(expense);
                        return;
                      }
                      await _archiveExpense(context, l10n, expense);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'edit', child: Text(l10n.t('edit'))),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(l10n.t('archive')),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  ExpenseGroup _localizedGroup(ExpenseGroup group, AppLocalizations l10n) {
    // Static group titles are matched on the stable group id, never on the
    // English text, so they translate in every locale.
    const idKeys = <String, String>{
      'list': 'allExpenses',
      'today': 'today',
      'yesterday': 'yesterday',
      'current_week': 'thisWeek',
      'current_month': 'thisMonth',
      'unassigned': 'unassigned',
    };
    final idKey = idKeys[group.id];
    final title = idKey != null
        ? l10n.t(idKey)
        : group.title == 'unassigned'
        ? l10n.t('unassigned')
        : switch (_groupBy) {
            ExpenseGroupMode.category => l10n.expenseCategoryLabel(group.title),
            ExpenseGroupMode.paymentMethod => l10n.paymentMethodLabel(
              group.title,
            ),
            _ => group.title,
          };
    return ExpenseGroup(
      id: group.id,
      title: title,
      totalAmount: group.totalAmount,
      transactionCount: group.transactionCount,
      items: group.items,
    );
  }

  String _entityTypeLabel(AppLocalizations l10n, String type) {
    return switch (type) {
      AccountingEntityTypes.supplier => l10n.t('supplier'),
      AccountingEntityTypes.vendor => l10n.t('supplier'),
      AccountingEntityTypes.worker => l10n.t('worker'),
      AccountingEntityTypes.contractor => l10n.t('contractor'),
      AccountingEntityTypes.transportProvider => l10n.t('transport'),
      AccountingEntityTypes.equipmentProvider => l10n.t('equipment'),
      AccountingEntityTypes.other => l10n.t('other'),
      _ => type,
    };
  }

  String _expenseSubtitle(
    Expense expense,
    String projectLabel,
    AppLocalizations l10n,
  ) {
    final parts = <String>[
      l10n.t(
        'projectDateWithValue',
        params: {
          'project': projectLabel,
          'date': expense.date.toIso8601String().split('T').first,
        },
      ),
    ];
    final entityLabel = expense.entityName.isNotEmpty
        ? expense.entityName
        : expense.supplierName;
    if (entityLabel.isNotEmpty) {
      parts.add(entityLabel);
    }
    if (expense.paymentMethod.isNotEmpty) {
      parts.add(l10n.paymentMethodLabel(expense.paymentMethod));
    }
    if (expense.paymentStatus.isNotEmpty) {
      parts.add(l10n.paymentStatusLabel(expense.paymentStatus));
    }
    final description = expense.description.isNotEmpty
        ? expense.description
        : expense.notes;
    if (description.isNotEmpty) {
      parts.add(description);
    }
    if (expense.attachments.isNotEmpty) {
      parts.add(
        '${expense.attachments.length} '
        '${expense.attachments.length == 1 ? l10n.t('attachment') : l10n.t('attachments')}',
      );
    }
    return parts.join(' • ');
  }
}

class _ExpenseSummaryCards extends StatelessWidget {
  const _ExpenseSummaryCards({
    required this.summary,
    required this.locale,
    required this.currency,
    required this.l10n,
  });

  final ExpenseQuickSummary summary;
  final String locale;
  final String currency;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCard(
              label: l10n.t('todayExpenses'),
              value: Formatters.money(
                summary.todayExpenses,
                currencyCode: currency,
                locale: locale,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryCard(
              label: l10n.t('weeklyExpenses'),
              value: Formatters.money(
                summary.weeklyExpenses,
                currencyCode: currency,
                locale: locale,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryCard(
              label: l10n.t('monthlyExpenses'),
              value: Formatters.money(
                summary.monthlyExpenses,
                currencyCode: currency,
                locale: locale,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryCard(
              label: l10n.t('transactionCount'),
              value: summary.transactionCount.toString(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}
