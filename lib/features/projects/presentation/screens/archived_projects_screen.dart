import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/navigation/app_route_observer.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/app_search_field.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ArchivedProjectsScreen extends ConsumerStatefulWidget {
  const ArchivedProjectsScreen({super.key});

  @override
  ConsumerState<ArchivedProjectsScreen> createState() =>
      _ArchivedProjectsScreenState();
}

class _ArchivedProjectsScreenState extends ConsumerState<ArchivedProjectsScreen>
    with RouteAutoRefreshMixin<ArchivedProjectsScreen> {
  static const _pageSize = 20;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  final List<Project> _projects = [];
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
        _projects.clear();
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
        _projects.clear();
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
          .read(projectRepositoryProvider)
          .fetchArchivedProjectsPage(
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

  Future<void> _deleteProject(Project project, AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('delete')),
        content: Text(l10n.t('confirmDeleteProjectCascade')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.t('delete'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
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

  Future<void> _unarchiveProject(Project project) async {
    await ref.read(projectRepositoryProvider).unarchiveProject(project.id);
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
          final haystack = '${project.name} ${project.clientName}'
              .toLowerCase();
          return haystack.contains(search);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filtered = _filteredProjects();

    return AppBackScope(
      fallbackRoute: AppRoutes.projects,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('archivedProjects'),
          fallbackRoute: AppRoutes.projects,
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
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n,
    List<Project> filtered,
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
              child: Column(
                children: [
                  Text(
                    appErrorMessage(l10n, _error),
                    style: const TextStyle(color: AppColors.danger),
                    textAlign: TextAlign.center,
                  ),
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.archive_outlined,
                  size: 64,
                  color: context.tokens.border,
                ),
                const SizedBox(height: 16),
                Text(
                  _projects.isEmpty
                      ? l10n.t('noArchivedProjects')
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= filtered.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final project = filtered[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.tokens.surface2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.architecture,
                      color: context.tokens.textMuted,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          project.clientName,
                          style: TextStyle(
                            color: context.tokens.textMuted,
                            fontSize: 13,
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
                      await _unarchiveProject(project);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'unarchive',
                        child: Row(
                          children: [
                            const Icon(Icons.unarchive_outlined, size: 20),
                            const SizedBox(width: 8),
                            Text(l10n.t('unarchive')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: AppColors.danger,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.t('delete'),
                              style: const TextStyle(color: AppColors.danger),
                            ),
                          ],
                        ),
                      ),
                    ],
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
