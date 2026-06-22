import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/accounting_entity_types.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/core/navigation/app_route_observer.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/active_filter_bar.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/app_search_field.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/common/presentation/controllers/transaction_bulk_archive_controller.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/entities/presentation/widgets/entity_autocomplete_field.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/reports/services/report_document_actions.dart';
import 'package:buildtrack_app/features/reports/services/report_pdf_exporter.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
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
  String? _paymentMethodFilter;
  String? _paymentStatusFilter;
  String? _entityFilterId;
  String _entityFilterName = '';
  String? _entityTypeFilter;
  DateTime? _startDateFilter;
  DateTime? _endDateFilter;
  bool _groupByEntity = false;

  bool get _hasActivePaymentFilters {
    return _paymentMethodFilter != null ||
        _paymentStatusFilter != null ||
        _entityFilterId != null ||
        _entityFilterName.isNotEmpty ||
        _entityTypeFilter != null ||
        _searchController.text.trim().isNotEmpty ||
        _startDateFilter != null ||
        _endDateFilter != null;
  }

  void _clearPaymentFilters() {
    setState(() {
      _paymentMethodFilter = null;
      _paymentStatusFilter = null;
      _entityFilterId = null;
      _entityFilterName = '';
      _entityTypeFilter = null;
      _startDateFilter = null;
      _endDateFilter = null;
      _searchController.clear();
    });
  }

  void _removePaymentFilter(String id) {
    setState(() {
      switch (id) {
        case 'method':
          _paymentMethodFilter = null;
        case 'status':
          _paymentStatusFilter = null;
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

  List<ActiveFilter> _activePaymentFilters(AppLocalizations l10n) {
    return [
      if (_paymentMethodFilter != null)
        ActiveFilter(
          id: 'method',
          label: l10n.paymentMethodLabel(_paymentMethodFilter!),
        ),
      if (_paymentStatusFilter != null)
        ActiveFilter(
          id: 'status',
          label: l10n.paymentStatusLabel(_paymentStatusFilter!),
        ),
      if (_entityFilterId != null || _entityFilterName.isNotEmpty)
        ActiveFilter(
          id: 'entity',
          label: '${l10n.t('entityName')}: $_entityFilterName',
        ),
      if (_entityTypeFilter != null)
        ActiveFilter(
          id: 'entityType',
          label: _entityTypeLabel(l10n, _entityTypeFilter!),
        ),
      if (_startDateFilter != null || _endDateFilter != null)
        ActiveFilter(
          id: 'date',
          label:
              '${_startDateFilter?.toIso8601String().split('T').first ?? 'Any'} - ${_endDateFilter?.toIso8601String().split('T').first ?? 'Any'}',
        ),
      if (_searchController.text.trim().isNotEmpty)
        ActiveFilter(
          id: 'search',
          label: 'Search: ${_searchController.text.trim()}',
        ),
    ];
  }

  Future<void> _openPaymentFilterSheet() async {
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
                            onPressed: () {
                              _clearPaymentFilters();
                              Navigator.of(context).pop();
                            },
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
            entityId: _entityFilterId,
            entityName: _entityFilterName,
            entityType: _entityTypeFilter,
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
    await context.push(
      AppRoutes.paymentEditPath(payment.id, projectId: _selectedProjectId),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _archivePayment(
    BuildContext context,
    AppLocalizations l10n,
    PaymentRecord payment,
  ) async {
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
      pushAppUiNotice(ref, l10n.t('queuedForSync'));
    }
  }

  Future<void> _archiveSelectedPayments(AppLocalizations l10n) async {
    final controller = ref.read(
      transactionBulkArchiveControllerProvider.notifier,
    );
    final result = await controller.archiveSelected(
      archiveOne: ref.read(paymentRepositoryProvider).archivePayment,
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
      _payments.removeWhere((item) => result.succeeded.contains(item.id));
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

  Future<void> _exportPdf({required bool share}) async {
    final l10n = AppLocalizations.of(context);
    final payments = _filteredPayments();
    if (payments.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.t('noDataYet'))));
      return;
    }
    final currency =
        ref.read(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
        'EGP';
    final filterParts = <String>[];
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
      final bytes = await const ReportPdfExporter().buildPaymentsListPdf(
        l10n: l10n,
        projectName: '',
        payments: payments,
        currency: currency,
        startDate: _startDateFilter,
        endDate: _endDateFilter,
        filterSummary: filterParts.isEmpty ? null : filterParts.join(', '),
      );
      final actions = ReportDocumentActions();
      final result = share
          ? await actions.shareDocument(bytes: bytes, filename: 'payments.pdf')
          : await actions.printDocument(bytes: bytes, name: l10n.t('payments'));
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

  List<PaymentRecord> _filteredPayments() {
    final search = _searchController.text.trim().toLowerCase();
    return _payments
        .where((payment) {
          if (_paymentMethodFilter != null &&
              payment.paymentMethod.toLowerCase() != _paymentMethodFilter) {
            return false;
          }
          if (_paymentStatusFilter != null &&
              payment.paymentStatus.toLowerCase() != _paymentStatusFilter) {
            return false;
          }
          if (_entityTypeFilter != null &&
              payment.entityType != _entityTypeFilter) {
            return false;
          }
          if (_entityFilterId != null && payment.entityId != _entityFilterId) {
            return false;
          }
          if (_entityFilterId == null &&
              _entityFilterName.isNotEmpty &&
              payment.entityName.toLowerCase() !=
                  _entityFilterName.toLowerCase()) {
            return false;
          }
          if (_startDateFilter != null &&
              payment.date.isBefore(_startDateFilter!)) {
            return false;
          }
          if (_endDateFilter != null && payment.date.isAfter(_endDateFilter!)) {
            return false;
          }
          if (search.isNotEmpty) {
            final haystack =
                '${payment.projectId} ${payment.description} ${payment.notes} ${payment.paymentMethod} ${payment.paymentStatus} ${payment.entityName} ${payment.entityType}'
                    .toLowerCase();
            if (!haystack.contains(search)) {
              return false;
            }
          }
          return true;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(projectsProvider);
    final filtered = _filteredPayments();
    final locale = Localizations.localeOf(context).languageCode;
    final currency =
        ref.watch(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
        'EGP';
    final bulkState = ref.watch(transactionBulkArchiveControllerProvider);
    final bulkController = ref.read(
      transactionBulkArchiveControllerProvider.notifier,
    );
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
          actions: bulkState.isSelecting
              ? [
                  IconButton(
                    tooltip: l10n.t('selectionMode'),
                    onPressed: bulkState.isInProgress
                        ? null
                        : () => bulkController.selectAll(
                            filtered.map((payment) => payment.id),
                          ),
                    icon: const Icon(Icons.select_all),
                  ),
                  IconButton(
                    tooltip: l10n.t('archiveSelected'),
                    onPressed: bulkState.isInProgress
                        ? null
                        : () => _archiveSelectedPayments(l10n),
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
                        child: Text(l10n.t('printReport')),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: Text(l10n.t('shareReport')),
                      ),
                    ],
                  ),
                ],
        ),
        floatingActionButton: bulkState.isSelecting
            ? null
            : FloatingActionButton.extended(
                onPressed: _openAddPayment,
                icon: const Icon(Icons.add),
                label: Text(l10n.t('addPayment')),
              ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: projectsAsync.when(
                data: (projects) => BelowDropdownField<String>(
                  label: l10n.t('project'),
                  value: _selectedProjectId ?? '',
                  entries: [
                    DropdownMenuEntry<String>(
                      value: '',
                      label: l10n.t('allProjectsOption'),
                    ),
                    ...projects.map(
                      (project) => DropdownMenuEntry<String>(
                        value: project.id,
                        label: project.name,
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    final projectId = value == null || value.isEmpty
                        ? null
                        : value;
                    if (_selectedProjectId == projectId) {
                      return;
                    }
                    setState(() {
                      _selectedProjectId = projectId;
                    });
                    context.go(AppRoutes.paymentsPath(projectId: projectId));
                    _refresh();
                  },
                ),
                error: (error, _) =>
                    AppRecoverableError(message: appErrorMessage(l10n, error)),
                loading: () => const AppLoadingSkeleton(
                  lineCount: 2,
                  padding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppSearchField(
                controller: _searchController,
                labelText: l10n.t('search'),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openPaymentFilterSheet,
                      icon: const Icon(Icons.filter_list),
                      label: const Text('Filters'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _groupByEntity = !_groupByEntity;
                    }),
                    icon: Icon(
                      _groupByEntity ? Icons.filter_alt_off : Icons.group_work,
                    ),
                    label: Text(
                      _groupByEntity
                          ? AppLocalizations.of(context).t('ungroup')
                          : AppLocalizations.of(context).t('groupByEntity'),
                    ),
                  ),
                ],
              ),
            ),
            if (_hasActivePaymentFilters)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: ActiveFilterBar(
                  filters: _activePaymentFilters(l10n),
                  onRemove: _removePaymentFilter,
                  onClearAll: _clearPaymentFilters,
                ),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: _groupByEntity
                    ? _buildGroupedContent(
                        context,
                        l10n,
                        filtered,
                        currency,
                        locale,
                      )
                    : _buildContent(context, l10n, filtered, currency, locale),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedContent(
    BuildContext context,
    AppLocalizations l10n,
    List<PaymentRecord> filtered,
    String currency,
    String locale,
  ) {
    if (filtered.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _hasActivePaymentFilters
                ? AppEmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    message: l10n.t('noFilterResults'),
                    actionLabel: l10n.t('clearFilters'),
                    onAction: _clearPaymentFilters,
                  )
                : AppEmptyState(
                    icon: Icons.payments_outlined,
                    message: l10n.t('noPaymentsYet'),
                    actionLabel: l10n.t('addPayment'),
                    onAction: _openAddPayment,
                  ),
          ),
        ],
      );
    }

    final groups = <String, List<PaymentRecord>>{};
    for (final payment in filtered) {
      final groupKey = payment.entityName.isNotEmpty
          ? payment.entityName
          : l10n.t('unassigned');
      groups.putIfAbsent(groupKey, () => []).add(payment);
    }

    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      children: groups.entries.map((entry) {
        final groupTotal = entry.value.fold<double>(
          0,
          (acc, item) => acc + item.amount,
        );
        return ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          title: Text('${entry.key} (${entry.value.length})'),
          subtitle: Text(
            l10n.t(
              'amountWithValue',
              params: {
                'value': Formatters.money(
                  groupTotal,
                  currencyCode: currency,
                  locale: locale,
                ),
              },
            ),
          ),
          children: entry.value.map((payment) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _paymentCard(context, l10n, payment, currency, locale),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n,
    List<PaymentRecord> filtered,
    String currency,
    String locale,
  ) {
    if (_isLoadingInitial && _payments.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 24),
          AppLoadingSkeleton(lineCount: 6),
        ],
      );
    }

    if (_error != null && _payments.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AppRecoverableError(
                message: appErrorMessage(l10n, _error),
                onRetry: _refresh,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _hasActivePaymentFilters
                ? AppEmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    message: l10n.t('noFilterResults'),
                    actionLabel: l10n.t('clearFilters'),
                    onAction: _clearPaymentFilters,
                  )
                : AppEmptyState(
                    icon: Icons.payments_outlined,
                    message: l10n.t('noPaymentsYet'),
                    actionLabel: l10n.t('addPayment'),
                    onAction: _openAddPayment,
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

        final payment = filtered[index];

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _paymentCard(context, l10n, payment, currency, locale),
        );
      },
    );
  }

  Widget _paymentCard(
    BuildContext context,
    AppLocalizations l10n,
    PaymentRecord payment,
    String currency,
    String locale,
  ) {
    final bulkState = ref.watch(transactionBulkArchiveControllerProvider);
    final bulkController = ref.read(
      transactionBulkArchiveControllerProvider.notifier,
    );
    final selected = bulkState.isSelected(payment.id);

    return Card(
      child: ListTile(
        selected: selected,
        leading: bulkState.isSelecting
            ? Checkbox(
                value: selected,
                onChanged: bulkState.isInProgress
                    ? null
                    : (_) => bulkController.toggle(payment.id),
              )
            : null,
        onLongPress: bulkState.isInProgress
            ? null
            : () => bulkController.toggle(payment.id),
        onTap: () {
          if (bulkState.isSelecting) {
            if (!bulkState.isInProgress) {
              bulkController.toggle(payment.id);
            }
            return;
          }
          context.push(
            AppRoutes.paymentDetailPath(
              payment.id,
              projectId: _selectedProjectId,
            ),
          );
        },
        title: Text(
          '${Formatters.money(payment.amount, currencyCode: currency, locale: locale)} | ${l10n.paymentMethodLabel(payment.paymentMethod)}',
        ),
        subtitle: Text(_paymentSubtitle(payment, l10n)),
        trailing: bulkState.isSelecting
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (payment.attachments.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.attach_file, size: 20),
                    ),
                  PopupMenuButton<String>(
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
                ],
              ),
      ),
    );
  }

  String _paymentSubtitle(PaymentRecord payment, AppLocalizations l10n) {
    final parts = <String>[
      l10n.t(
        'projectDateWithValue',
        params: {
          'project': payment.projectId,
          'date': payment.date.toIso8601String().split('T').first,
        },
      ),
    ];
    if (payment.entityName.isNotEmpty) {
      parts.add(payment.entityName);
    }
    if (payment.paymentStatus.isNotEmpty) {
      parts.add(l10n.paymentStatusLabel(payment.paymentStatus));
    }
    final description = payment.description.isNotEmpty
        ? payment.description
        : payment.notes;
    if (description.isNotEmpty) {
      parts.add(description);
    }
    if (payment.attachments.isNotEmpty) {
      parts.add(
        '${payment.attachments.length} '
        '${payment.attachments.length == 1 ? l10n.t('attachment') : l10n.t('attachments')}',
      );
    }
    return parts.join(' • ');
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
}
