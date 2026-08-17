import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_route_observer.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/app_search_field.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Active (non-archived) projects with project_metrics merged in, so consumers
/// see real totalExpenses/totalPayments/netProfit rather than the bare project
/// doc's zero defaults. The dashboard reads this for its per-project financial
/// section, profit margin, and the over-budget alerts strip — all of which were
/// stuck at 0 when this used the non-merging `watchProjects`, even though the
/// metrics-merged Projects browse list showed the correct values.
final projectsProvider = StreamProvider<List<Project>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  return ref
      .watch(projectRepositoryProvider)
      .watchAllProjects(workspaceId)
      .map(
        (projects) =>
            projects.where((project) => !project.isArchived).toList(),
      );
});

final allProjectsProvider = StreamProvider<List<Project>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  return ref.watch(projectRepositoryProvider).watchAllProjects(workspaceId);
});

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen>
    with RouteAutoRefreshMixin<ProjectsScreen> {
  static const _pageSize = 20;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  ProviderSubscription<int>? _pendingSyncSubscription;
  ProviderSubscription<int>? _deadLetterSubscription;

  final List<Project> _projects = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  Object? _error;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _isRefreshing = false;
  bool _hasMore = true;
  String? _workspaceId;
  String? _statusFilter;
  ProjectBrowseSort _sort = ProjectBrowseSort.recent;
  bool _canAccessFinancial = false;
  bool _roleResolved = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
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

  Future<void> _refresh({bool preserveVisibleProjects = true}) async {
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    _workspaceId = workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _projects.clear();
        _cursor = null;
        _error = null;
        _hasMore = false;
        _isLoadingInitial = false;
        _isLoadingMore = false;
        _isRefreshing = false;
      });
      return;
    }

    final showInitialLoading = !preserveVisibleProjects || _projects.isEmpty;
    if (mounted) {
      setState(() {
        if (showInitialLoading) {
          _projects.clear();
        }
        _cursor = null;
        _error = null;
        _hasMore = true;
        _isLoadingInitial = showInitialLoading;
        _isLoadingMore = false;
        _isRefreshing = !showInitialLoading;
      });
    }

    await _loadMore(reset: true, showInitialLoading: showInitialLoading);
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

  Future<void> _loadMore({
    bool reset = false,
    bool showInitialLoading = true,
  }) async {
    final workspaceId = _workspaceId ?? ref.read(activeWorkspaceIdProvider);
    if (workspaceId == null || workspaceId.isEmpty) {
      return;
    }
    if (!reset &&
        (_isLoadingInitial || _isLoadingMore || _isRefreshing || !_hasMore)) {
      return;
    }

    if (mounted) {
      setState(() {
        _error = null;
        if (reset) {
          _isLoadingInitial = showInitialLoading;
          _isLoadingMore = false;
          _isRefreshing = !showInitialLoading;
        } else {
          _isLoadingMore = true;
        }
      });
    }

    try {
      final repository = ref.read(projectRepositoryProvider);
      final page = repository is ProjectBrowseRepository
          ? await (repository as ProjectBrowseRepository)
                .fetchProjectBrowsePage(
                  ProjectBrowseQuery(
                    workspaceId: workspaceId,
                    status: _statusFilter,
                    sort: _canAccessFinancial || !_sort.isFinancial
                        ? _sort
                        : ProjectBrowseSort.recent,
                    pageSize: _pageSize,
                  ),
                  cursor: reset ? null : _cursor,
                )
          : await repository.fetchProjectsPage(
              workspaceId,
              cursor: reset ? null : _cursor,
              pageSize: _pageSize,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _projects
            ..clear()
            ..addAll(page.items);
        } else {
          _projects.addAll(page.items);
        }
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _error = null;
        _isLoadingInitial = false;
        _isLoadingMore = false;
        _isRefreshing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoadingInitial = false;
        _isLoadingMore = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _openCreateProject() async {
    await context.push(AppRoutes.createProject);
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _archiveProject(Project project, AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('archive')),
        content: Text(l10n.t('confirmArchiveProject')),
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
    if (confirmed != true) return;
    await ref.read(projectRepositoryProvider).archiveProject(project.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _projects.removeWhere((item) => item.id == project.id);
    });
  }

  Future<void> _deleteProject(Project project, AppLocalizations l10n) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final matches = controller.text.trim() == project.name.trim();
          return AlertDialog(
            title: Text(l10n.t('delete')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.t('confirmDeleteProjectCascade')),
                const SizedBox(height: 16),
                Text(
                  l10n.t('deleteProjectTypeNameToConfirm'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(hintText: project.name),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.t('cancel')),
              ),
              TextButton(
                onPressed: matches ? () => Navigator.pop(context, true) : null,
                child: Text(
                  l10n.t('delete'),
                  style: TextStyle(
                    color: matches
                        ? context.tokens.expense
                        : context.tokens.textMuted,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (confirmed != true) {
      return;
    }

    await ref.read(projectRepositoryProvider).deleteProject(project.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _projects.removeWhere((item) => item.id == project.id);
    });
  }

  List<Project> _filteredProjects() {
    final search = _searchController.text.trim().toLowerCase();
    if (search.isEmpty) {
      return List<Project>.unmodifiable(_projects);
    }
    return _projects
        .where((project) {
          final haystack =
              '${project.name} ${project.clientName} ${project.status}'
                  .toLowerCase();
          return haystack.contains(search);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final roleAsync = ref.watch(currentAccountingRoleProvider);
    final canAccessFinancial = roleAsync.value?.canAccessAccounting == true;
    if (roleAsync.hasValue &&
        (!_roleResolved || _canAccessFinancial != canAccessFinancial)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _roleResolved = true;
          _canAccessFinancial = canAccessFinancial;
          if (!canAccessFinancial && _sort.isFinancial) {
            _sort = ProjectBrowseSort.recent;
          }
        });
        unawaited(_refresh());
      });
    }
    final filtered = _filteredProjects();
    final locale = Localizations.localeOf(context).languageCode;
    final currency =
        ref.watch(currentUserSettingsProvider).value?.defaultCurrency ?? 'EGP';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('projects')),
        actions: [
          IconButton(
            key: const Key('qa_projects_new'),
            tooltip: l10n.t('newProject'),
            onPressed: _openCreateProject,
            icon: const Icon(Icons.add),
          ),
          if (_canAccessFinancial)
            IconButton(
              tooltip: l10n.t('reports'),
              onPressed: () => context.push(AppRoutes.reportsPath()),
              icon: const Icon(Icons.assessment_outlined),
            ),
          IconButton(
            tooltip: l10n.t('archivedProjects'),
            onPressed: () => context.push(AppRoutes.archivedProjects),
            icon: const Icon(Icons.archive_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: AppSearchField(
                controller: _searchController,
                labelText: l10n.t('search'),
              ),
            ),
            const SizedBox(height: 12),
            _ProjectBrowseControls(
              status: _statusFilter,
              sort: _sort,
              canAccessFinancial: _canAccessFinancial,
              l10n: l10n,
              onStatusChanged: (value) {
                setState(() => _statusFilter = value);
                unawaited(_refresh(preserveVisibleProjects: false));
              },
              onSortChanged: (value) {
                setState(() => _sort = value);
                unawaited(_refresh(preserveVisibleProjects: false));
              },
            ),
            if (_roleResolved && !_canAccessFinancial)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l10n.t('projectFinancialAccessRestricted')),
                    ),
                  ],
                ),
              ),
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
    List<Project> filtered,
    String currency,
    String locale,
  ) {
    if (_isLoadingInitial && _projects.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 24),
          AppLoadingSkeleton(lineCount: 6),
        ],
      );
    }

    if (_error != null && _projects.isEmpty) {
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
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 64,
                  color: context.tokens.border,
                ),
                const SizedBox(height: 16),
                Text(
                  _projects.isEmpty
                      ? l10n.t('noProjectsYet')
                      : l10n.t('noDataYet'),
                  style: TextStyle(
                    color: context.tokens.textMuted,
                    fontSize: 16,
                  ),
                ),
              ],
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

        final project = filtered[index];
        final t = context.tokens;
        final positiveProfit = project.netProfit >= 0;
        final profitColor = positiveProfit ? t.income : t.expense;
        final isActiveStatus = project.status == 'active';
        final netAmountText =
            '${positiveProfit ? '+' : '−'}'
            '${Formatters.money(project.netProfit.abs(), currencyCode: currency, locale: locale)}';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: BuildCard(
            onTap: () => context.push(AppRoutes.projectDetailPath(project.id)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.accentSoft,
                        borderRadius: t.radiusMd,
                      ),
                      child: Icon(Icons.apartment_outlined, color: t.accent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isActiveStatus ? t.incomeSoft : t.surface2,
                              borderRadius: t.radiusSm,
                            ),
                            child: Text(
                              l10n.projectStatusLabel(project.status),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isActiveStatus ? t.income : t.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'delete') {
                          await _deleteProject(project, l10n);
                          return;
                        }
                        await _archiveProject(project, l10n);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'archive',
                          child: Row(
                            children: [
                              const Icon(Icons.archive_outlined, size: 20),
                              const SizedBox(width: 8),
                              Text(l10n.t('archive')),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: t.expense,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.t('delete'),
                                style: TextStyle(color: t.expense),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_canAccessFinancial) ...[
                  const SizedBox(height: 12),
                  // Profit on its own line so the project name (above) keeps the
                  // full card width instead of being squeezed to a few
                  // characters by a long money value sharing its row.
                  //
                  // In expense-ledger mode "profit"/"loss" is the wrong frame
                  // entirely — the project has no income to profit from — so
                  // the card states the expense total instead.
                  if (project.isExpenseLedger)
                    Row(
                      children: [
                        Icon(
                          Icons.trending_down,
                          size: 18,
                          color: t.expense,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          Formatters.money(
                            project.totalExpenses,
                            currencyCode: currency,
                            locale: locale,
                          ),
                          style: TextStyle(
                            color: t.expense,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.t('totalExpenses'),
                          style: TextStyle(color: t.textMuted, fontSize: 12),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Icon(
                          positiveProfit
                              ? Icons.trending_up
                              : Icons.trending_down,
                          size: 18,
                          color: profitColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          netAmountText,
                          style: TextStyle(
                            color: profitColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          positiveProfit ? l10n.t('profit') : l10n.t('loss'),
                          style: TextStyle(color: t.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                ],
                // Deliberately hasBudgetLimit, not hasBudget: the card has
                // always required an explicit Budget Limit, and FR-018 forbids
                // changing how contract-bearing projects render. The rule now
                // lives on the model rather than inline, so it is still stated
                // once, but its narrower meaning is preserved.
                if (_canAccessFinancial && project.hasBudgetLimit) ...[
                  const SizedBox(height: 14),
                  _BudgetBar(
                    spent: project.totalExpenses,
                    budget: project.budgetLimit!,
                    currency: currency,
                    locale: locale,
                    l10n: l10n,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProjectBrowseControls extends StatelessWidget {
  const _ProjectBrowseControls({
    required this.status,
    required this.sort,
    required this.canAccessFinancial,
    required this.l10n,
    required this.onStatusChanged,
    required this.onSortChanged,
  });

  final String? status;
  final ProjectBrowseSort sort;
  final bool canAccessFinancial;
  final AppLocalizations l10n;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<ProjectBrowseSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final statuses = <(String?, String)>[
      (null, l10n.t('allStatuses')),
      ('active', l10n.projectStatusLabel('active')),
      ('completed', l10n.projectStatusLabel('completed')),
      ('paused', l10n.projectStatusLabel('paused')),
    ];
    final sorts = <(ProjectBrowseSort, String)>[
      (ProjectBrowseSort.recent, l10n.t('projectSortRecent')),
      (ProjectBrowseSort.name, l10n.t('projectSortName')),
      if (canAccessFinancial) ...[
        (ProjectBrowseSort.highestExpense, l10n.t('projectSortHighestExpense')),
        (ProjectBrowseSort.highestIncome, l10n.t('projectSortHighestIncome')),
        (ProjectBrowseSort.highestNet, l10n.t('projectSortHighestNet')),
      ],
    ];

    final selectedStatus = statuses.firstWhere((item) => item.$1 == status).$2;
    final selectedSort = sorts.firstWhere((item) => item.$1 == sort).$2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _ProjectMenuButton<String?>(
              key: const Key('qa_projects_filter'),
              icon: Icons.filter_list,
              label: selectedStatus,
              items: statuses,
              value: status,
              onSelected: onStatusChanged,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ProjectMenuButton<ProjectBrowseSort>(
              key: const Key('qa_projects_sort'),
              icon: Icons.sort,
              label: selectedSort,
              items: sorts,
              value: sort,
              onSelected: onSortChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectMenuButton<T> extends StatelessWidget {
  const _ProjectMenuButton({
    required super.key,
    required this.icon,
    required this.label,
    required this.items,
    required this.value,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => items
          .map(
            (item) => PopupMenuItem<T>(
              value: item.$1,
              child: Row(
                children: [
                  if (item.$1 == value) const Icon(Icons.check, size: 18),
                  if (item.$1 == value) const SizedBox(width: 8),
                  Text(item.$2),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: context.tokens.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// Thin budget-vs-spend indicator shown on project cards when a budget is set.
class _BudgetBar extends StatelessWidget {
  const _BudgetBar({
    required this.spent,
    required this.budget,
    required this.currency,
    required this.locale,
    required this.l10n,
  });

  final double spent;
  final double budget;
  final String currency;
  final String locale;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ratio = budget <= 0 ? 0.0 : spent / budget;
    final over = ratio > 1.0;
    final color = budgetProgressColor(t, ratio);
    final remaining = budget - spent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedProgressBar(
          value: ratio.clamp(0.0, 1.0).toDouble(),
          minHeight: 6,
          backgroundColor: t.surface3,
          color: color,
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                '${Formatters.money(spent, currencyCode: currency, locale: locale)} / ${Formatters.money(budget, currencyCode: currency, locale: locale)}',
                style: TextStyle(fontSize: 11, color: context.tokens.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              over
                  ? l10n.t('overBudget')
                  : '${(ratio * 100).round()}% ${l10n.t('budgetUsed')}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        if (!over) ...[
          const SizedBox(height: 2),
          Text(
            '${Formatters.money(remaining, currencyCode: currency, locale: locale)} ${l10n.t('remaining')}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ],
    );
  }
}
