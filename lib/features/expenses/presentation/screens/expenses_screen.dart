import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/navigation/app_route_observer.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  Object? _error;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _workspaceId;

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
    final messenger = ScaffoldMessenger.of(context);
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
      // messenger.showSnackBar(
      //   SnackBar(content: Text(l10n.t('queuedForSync'))),
      // );
    }
  }

  List<Expense> _filteredExpenses() {
    final search = _searchController.text.trim().toLowerCase();
    if (search.isEmpty) {
      return List<Expense>.unmodifiable(_expenses);
    }
    return _expenses
        .where((expense) {
          final haystack =
              '${expense.projectName} ${expense.category} ${expense.notes} ${expense.supplierName}'
                  .toLowerCase();
          return haystack.contains(search);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filtered = _filteredExpenses();

    return AppBackScope(
      fallbackRoute: AppRoutes.projectDetailPath(widget.projectId),
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('expenseList'),
          fallbackRoute: AppRoutes.projectDetailPath(widget.projectId),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddExpense,
          icon: const Icon(Icons.add),
          label: Text(l10n.t('addExpense')),
        ),
        body: Column(
          children: [
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
            const SizedBox(height: 16),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: _buildContent(context, l10n, filtered),
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
  ) {
    if (_isLoadingInitial && _expenses.isEmpty) {
      return const Center(child: CircularProgressIndicator());
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
              _expenses.isEmpty ? l10n.t('noExpensesYet') : l10n.t('noDataYet'),
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

        final expense = filtered[index];
        final projectLabel = expense.projectName.isEmpty
            ? expense.projectId
            : expense.projectName;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              onTap: () => context.push(
                AppRoutes.expenseDetailPath(
                  expense.id,
                  projectId: widget.projectId,
                ),
              ),
              title: Text(
                '${expense.amount.toStringAsFixed(0)} ${expense.currency} | ${l10n.expenseCategoryLabel(expense.category)}',
              ),
              subtitle: Text(
                l10n.t(
                  'projectDateWithValue',
                  params: {
                    'project': projectLabel,
                    'date': expense.date.toIso8601String().split('T').first,
                  },
                ),
              ),
              trailing: PopupMenuButton<String>(
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
                    value: 'delete',
                    child: Text(l10n.t('archive')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
