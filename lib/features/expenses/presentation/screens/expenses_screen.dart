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
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/data/expense_summary_providers.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/presentation/models/expense_group.dart';
import 'package:buildtrack_app/features/expenses/presentation/widgets/expense_group_section.dart';
import 'package:buildtrack_app/features/entities/presentation/widgets/entity_autocomplete_field.dart';
import 'package:buildtrack_app/features/reports/services/report_pdf_exporter.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

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
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
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
                        const DropdownMenuEntry(value: '', label: 'All'),
                        DropdownMenuEntry(
                          value: 'labor',
                          label: l10n.expenseCategoryLabel('labor'),
                        ),
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
                        const DropdownMenuEntry(value: '', label: 'All'),
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
                        const DropdownMenuEntry(value: '', label: 'All'),
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
                            child: const Text('Clear filters'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Apply'),
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

  Future<void> _openAddExpense() async {
    await context.push(AppRoutes.addExpensePath(projectId: widget.projectId));
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

  Future<void> _exportPdf() async {
    final l10n = AppLocalizations.of(context);
    final expenses = _filteredExpenses();
    if (expenses.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.t('noDataYet'))));
      return;
    }
    final currency =
        ref.read(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
        'EGP';
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
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${l10n.t('failed')}: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filtered = _filteredExpenses();
    final locale = Localizations.localeOf(context).languageCode;
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
          actions: [
            IconButton(
              tooltip: l10n.t('exportPdf'),
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddExpense,
          icon: const Icon(Icons.add),
          label: Text(l10n.t('addExpense')),
        ),
        body: Column(
          children: [
            summaryAsync.when(
              data: (summary) => _ExpenseSummaryCards(
                summary: summary,
                locale: locale,
                currency: 'EGP',
                l10n: l10n,
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(error.toString()),
              ),
              loading: () => const LinearProgressIndicator(minHeight: 2),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: l10n.t('search'),
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openExpenseFilterSheet,
                      icon: const Icon(Icons.filter_list),
                      label: Text(l10n.t('filters')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => context.push(AppRoutes.addEntry),
                      icon: const Icon(Icons.flash_on),
                      label: Text(l10n.t('quickEntry')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_categoryFilter != null)
                      FilterChip(
                        label: Text(
                          l10n.expenseCategoryLabel(_categoryFilter!),
                        ),
                        onSelected: (_) => _clearExpenseFilters(),
                      ),
                    if (_paymentMethodFilter != null)
                      FilterChip(
                        label: Text(
                          l10n.paymentMethodLabel(_paymentMethodFilter!),
                        ),
                        onSelected: (_) => _clearExpenseFilters(),
                      ),
                    if (_paymentStatusFilter != null)
                      FilterChip(
                        label: Text(
                          l10n.paymentStatusLabel(_paymentStatusFilter!),
                        ),
                        onSelected: (_) => _clearExpenseFilters(),
                      ),
                    if (_supplierFilter != null)
                      FilterChip(
                        label: Text(
                          '${l10n.t('supplierName')}: $_supplierFilter',
                        ),
                        onSelected: (_) => _clearExpenseFilters(),
                      ),
                    if (_entityFilterId != null)
                      FilterChip(
                        label: Text(
                          _entityFilterName.isNotEmpty
                              ? '${l10n.t('entityName')}: $_entityFilterName'
                              : l10n.t('entitySummary'),
                        ),
                        onSelected: (_) => _clearExpenseFilters(),
                      ),
                    if (_entityTypeFilter != null)
                      FilterChip(
                        label: Text(_entityTypeLabel(l10n, _entityTypeFilter!)),
                        onSelected: (_) => _clearExpenseFilters(),
                      ),
                    if (_startDateFilter != null || _endDateFilter != null)
                      FilterChip(
                        label: Text(
                          '${_startDateFilter?.toIso8601String().split('T').first ?? 'Any'} – ${_endDateFilter?.toIso8601String().split('T').first ?? 'Any'}',
                        ),
                        onSelected: (_) => _clearExpenseFilters(),
                      ),
                    if (_searchController.text.trim().isNotEmpty)
                      FilterChip(
                        label: Text('Search: ${_searchController.text.trim()}'),
                        onSelected: (_) => _clearExpenseFilters(),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.clear),
                      label: Text(l10n.t('clearFilters')),
                      onPressed: _clearExpenseFilters,
                    ),
                  ],
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
      return const SizedBox.shrink();
    }

    if (_error != null && _expenses.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(_error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _refresh,
                    child: Text(l10n.t('retry')),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

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

    final itemCount = filtered.length + (_isLoadingMore ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
    final projectLabel = expense.projectName.isEmpty
        ? expense.projectId
        : expense.projectName;
    return Card(
      child: ListTile(
        onTap: () => context.push(
          AppRoutes.expenseDetailPath(expense.id, projectId: widget.projectId),
        ),
        title: Text(
          '${Formatters.money(expense.amount, currencyCode: expense.currency, locale: locale)} | ${l10n.expenseCategoryLabel(expense.category)}',
        ),
        subtitle: Text(_expenseSubtitle(expense, projectLabel, l10n)),
        trailing: Row(
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
                PopupMenuItem(value: 'delete', child: Text(l10n.t('archive'))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ExpenseGroup _localizedGroup(ExpenseGroup group, AppLocalizations l10n) {
    final title = switch (_groupBy) {
      ExpenseGroupMode.category => l10n.expenseCategoryLabel(group.title),
      ExpenseGroupMode.paymentMethod => l10n.paymentMethodLabel(group.title),
      _ => group.title,
    };
    return ExpenseGroup(
      id: group.id,
      title: title == 'Unassigned' ? l10n.t('unassigned') : title,
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
