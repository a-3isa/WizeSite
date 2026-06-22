import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/navigation/app_route_observer.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/app_search_field.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final workersProvider = StreamProvider<List<WorkerProfile>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  return ref.watch(workerRepositoryProvider).watchWorkers(workspaceId);
});

class WorkersScreen extends ConsumerStatefulWidget {
  const WorkersScreen({super.key});

  @override
  ConsumerState<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends ConsumerState<WorkersScreen>
    with RouteAutoRefreshMixin<WorkersScreen> {
  static const _pageSize = 20;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  final List<WorkerProfile> _workers = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  Object? _error;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _workspaceId;
  WorkerStatus? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
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
        _workers.clear();
        _cursor = null;
        _error = null;
        _hasMore = false;
        _isLoadingInitial = false;
        _isLoadingMore = false;
      });
      return;
    }

    final provisioned = ref.read(workersProvider).valueOrNull;
    if (provisioned != null && mounted) {
      setState(() {
        _workers
          ..clear()
          ..addAll(provisioned);
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
        _workers.clear();
        _cursor = null;
        _error = null;
        _hasMore = true;
        _isLoadingInitial = true;
        _isLoadingMore = false;
      });
    }

    await _loadMore(reset: true);
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
          .read(workerRepositoryProvider)
          .fetchWorkersPage(
            workspaceId,
            cursor: reset ? null : _cursor,
            pageSize: _pageSize,
            statuses: _selectedStatus == null ? null : {_selectedStatus!},
          );
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _workers
            ..clear()
            ..addAll(page.items);
        } else {
          _workers.addAll(page.items);
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

  Future<void> _openAddWorker() async {
    await context.push(AppRoutes.addWorker);
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _openEditWorker(WorkerProfile worker) async {
    await context.push(AppRoutes.workerEditPath(worker.id));
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _archiveWorker(WorkerProfile worker) async {
    await ref.read(workerRepositoryProvider).archiveWorker(worker.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _workers.removeWhere((item) => item.id == worker.id);
    });
  }

  List<WorkerProfile> _filteredWorkers() {
    final search = _searchController.text.trim().toLowerCase();
    return _workers
        .where((worker) {
          if (_selectedStatus != null && worker.status != _selectedStatus) {
            return false;
          }
          if (search.isEmpty) {
            return true;
          }
          final haystack =
              '${worker.name} ${worker.phoneNumber} ${worker.workerType}'
                  .toLowerCase();
          return haystack.contains(search);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workersProvider, (_, next) {
      if (!mounted) return;
      final items = next.valueOrNull;
      if (items != null) {
        setState(() {
          _workers
            ..clear()
            ..addAll(items);
          _isLoadingInitial = false;
          _hasMore = false;
        });
      }
    });
    final l10n = AppLocalizations.of(context);
    final filtered = _filteredWorkers();
    final locale = Localizations.localeOf(context).languageCode;
    final currency =
        ref.watch(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
        'EGP';

    return AppBackScope(
      fallbackRoute: AppRoutes.projects,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('workerDirectory'),
          fallbackRoute: AppRoutes.projects,
          actions: [
            TextButton.icon(
              key: const Key('qa_worker_add'),
              onPressed: _openAddWorker,
              icon: const Icon(Icons.add),
              label: Text(l10n.t('add')),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: AppSearchField(
                controller: _searchController,
                labelText: l10n.t('search'),
              ),
            ),
            const SizedBox(height: 16),
            _StatusFilters(
              selectedStatus: _selectedStatus,
              onSelected: (status) {
                setState(() => _selectedStatus = status);
                _refresh();
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: _buildContent(context, l10n, filtered, currency, locale),
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
    List<WorkerProfile> filtered,
    String currency,
    String locale,
  ) {
    if (_isLoadingInitial && _workers.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 24),
          AppLoadingSkeleton(lineCount: 6),
        ],
      );
    }

    if (_error != null && _workers.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AppRecoverableError(
              message: appErrorMessage(l10n, _error),
              onRetry: _refresh,
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
          const SizedBox(height: 80),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AppEmptyState(
              message: _workers.isEmpty
                  ? l10n.t('noWorkersYet')
                  : l10n.t('noDataYet'),
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

        final worker = filtered[index];

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              onTap: () => context.push(AppRoutes.workerDetailPath(worker.id)),
              leading: const Icon(Icons.engineering),
              title: Text(worker.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${worker.phoneNumber} | ${worker.billingType == 'project' ? l10n.t('billingTypeProject') : l10n.t(
                            'wageWithValue',
                            params: {'value': Formatters.money(worker.dailyWage, currencyCode: currency, locale: locale)},
                          )}',
                  ),
                  const SizedBox(height: 6),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_workerStatusLabel(l10n, worker.status)),
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                key: Key('qa_worker_actions_${worker.id}'),
                onSelected: (value) async {
                  if (value == 'edit') {
                    await _openEditWorker(worker);
                    return;
                  }
                  await _archiveWorker(worker);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(l10n.t('edit'))),
                  PopupMenuItem(value: 'delete', child: Text(l10n.t('delete'))),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _workerStatusLabel(AppLocalizations l10n, WorkerStatus status) {
    return switch (status) {
      WorkerStatus.active => l10n.t('workerStatusActive'),
      WorkerStatus.inactive => l10n.t('workerStatusInactive'),
      WorkerStatus.terminated => l10n.t('workerStatusTerminated'),
    };
  }
}

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({
    required this.selectedStatus,
    required this.onSelected,
  });

  final WorkerStatus? selectedStatus;
  final ValueChanged<WorkerStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filters = <(WorkerStatus?, String)>[
      (null, l10n.t('all')),
      (WorkerStatus.active, _workerStatusLabel(l10n, WorkerStatus.active)),
      (WorkerStatus.inactive, _workerStatusLabel(l10n, WorkerStatus.inactive)),
      (
        WorkerStatus.terminated,
        _workerStatusLabel(l10n, WorkerStatus.terminated),
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final filter in filters)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilterChip(
                label: Text(filter.$2),
                selected: selectedStatus == filter.$1,
                onSelected: (_) => onSelected(filter.$1),
              ),
            ),
        ],
      ),
    );
  }

  String _workerStatusLabel(AppLocalizations l10n, WorkerStatus status) {
    return switch (status) {
      WorkerStatus.active => l10n.t('workerStatusActive'),
      WorkerStatus.inactive => l10n.t('workerStatusInactive'),
      WorkerStatus.terminated => l10n.t('workerStatusTerminated'),
    };
  }
}
