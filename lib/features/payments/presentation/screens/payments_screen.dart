import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_route_observer.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({this.projectId, super.key});

  final String? projectId;

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen>
    with RouteAutoRefreshMixin<PaymentsScreen> {
  static const _pageSize = 20;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  ProviderSubscription<int>? _pendingSyncSubscription;
  ProviderSubscription<int>? _deadLetterSubscription;

  final List<PaymentRecord> _payments = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  Object? _error;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _workspaceId;
  String? _selectedProjectId;

  @override
  void initState() {
    super.initState();
    _selectedProjectId = widget.projectId;
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
  void didUpdateWidget(covariant PaymentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _selectedProjectId = widget.projectId;
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
        _payments.clear();
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
        _payments.clear();
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
          .read(paymentRepositoryProvider)
          .fetchPaymentsPage(
            workspaceId,
            projectId: _selectedProjectId,
            cursor: reset ? null : _cursor,
            pageSize: _pageSize,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _payments
            ..clear()
            ..addAll(page.items);
        } else {
          _payments.addAll(page.items);
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

  Future<void> _openAddPayment() async {
    await context.push(AppRoutes.addPaymentPath(projectId: _selectedProjectId));
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _openEditPayment(PaymentRecord payment) async {
    await context.push(AppRoutes.paymentEditPath(payment.id));
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _archivePayment(
    BuildContext context,
    AppLocalizations l10n,
    PaymentRecord payment,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('archive')),
        content: Text(l10n.t('confirmArchivePayment')),
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
        .read(paymentRepositoryProvider)
        .archivePayment(payment.id);
    if (!mounted) {
      return;
    }

    setState(() {
      _payments.removeWhere((item) => item.id == payment.id);
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

  List<PaymentRecord> _filteredPayments() {
    final search = _searchController.text.trim().toLowerCase();
    if (search.isEmpty) {
      return List<PaymentRecord>.unmodifiable(_payments);
    }
    return _payments
        .where((payment) {
          final haystack =
              '${payment.projectId} ${payment.notes} ${payment.paymentMethod}'
                  .toLowerCase();
          return haystack.contains(search);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(projectsProvider);
    final filtered = _filteredPayments();
    final fallbackRoute =
        _selectedProjectId == null || _selectedProjectId!.isEmpty
        ? AppRoutes.projects
        : AppRoutes.projectDetailPath(_selectedProjectId!);

    return AppBackScope(
      fallbackRoute: fallbackRoute,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('payments'),
          fallbackRoute: fallbackRoute,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddPayment,
          icon: const Icon(Icons.add),
          label: Text(l10n.t('addPayment')),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: projectsAsync.when(
                data: (projects) => DropdownButtonFormField<String?>(
                  initialValue: _selectedProjectId,
                  decoration: InputDecoration(labelText: l10n.t('project')),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.t('allProjectsOption')),
                    ),
                    ...projects.map(
                      (project) => DropdownMenuItem<String?>(
                        value: project.id,
                        child: Text(project.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (_selectedProjectId == value) {
                      return;
                    }
                    setState(() {
                      _selectedProjectId = value;
                    });
                    context.go(AppRoutes.paymentsPath(projectId: value));
                    _refresh();
                  },
                ),
                error: (error, _) => Text(error.toString()),
                loading: () => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
    List<PaymentRecord> filtered,
  ) {
    if (_isLoadingInitial && _payments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _payments.isEmpty) {
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
          Center(child: Text(l10n.t('noPaymentsYet'))),
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

        final payment = filtered[index];

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              onTap: () =>
                  context.push(AppRoutes.paymentDetailPath(payment.id)),
              title: Text(
                '${payment.amount.toStringAsFixed(0)} | ${l10n.paymentMethodLabel(payment.paymentMethod)}',
              ),
              subtitle: Text(
                l10n.t(
                  'projectDateWithValue',
                  params: {
                    'project': payment.projectId,
                    'date': payment.date.toIso8601String().split('T').first,
                  },
                ),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    await _openEditPayment(payment);
                    return;
                  }
                  await _archivePayment(context, l10n, payment);
                },
                itemBuilder: (_) => [
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
