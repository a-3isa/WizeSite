import 'dart:async';

import 'package:buildtrack_app/core/pagination/record_page.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:flutter_riverpod/legacy.dart';

typedef ReportProjectPageLoader =
    Future<RecordPage<Project>> Function({Object? cursor});

class ReportProjectSelectorState {
  const ReportProjectSelectorState({
    this.projects = const [],
    this.showingArchived = false,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<Project> projects;
  final bool showingArchived;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  ReportProjectSelectorState copyWith({
    List<Project>? projects,
    bool? showingArchived,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) {
    return ReportProjectSelectorState(
      projects: projects ?? this.projects,
      showingArchived: showingArchived ?? this.showingArchived,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class ReportProjectSelectorController
    extends StateNotifier<ReportProjectSelectorState> {
  ReportProjectSelectorController({
    required ReportProjectPageLoader loadActivePage,
    required ReportProjectPageLoader loadArchivedPage,
  }) : _loadActivePage = loadActivePage,
       _loadArchivedPage = loadArchivedPage,
       super(const ReportProjectSelectorState());

  final ReportProjectPageLoader _loadActivePage;
  final ReportProjectPageLoader _loadArchivedPage;
  Object? _cursor;

  Future<void> loadInitial() async {
    _cursor = null;
    state = state.copyWith(
      projects: const [],
      isLoading: true,
      isLoadingMore: false,
      hasMore: true,
      clearError: true,
    );
    await _load(reset: true);
  }

  Future<void> showArchived(bool value) async {
    if (state.showingArchived == value && state.projects.isNotEmpty) return;
    state = state.copyWith(showingArchived: value);
    await loadInitial();
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    await _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    try {
      final loader = state.showingArchived
          ? _loadArchivedPage
          : _loadActivePage;
      final page = await loader(cursor: reset ? null : _cursor);
      _cursor = page.nextCursor;
      state = state.copyWith(
        projects: reset ? page.items : [...state.projects, ...page.items],
        isLoading: false,
        isLoadingMore: false,
        hasMore: page.hasMore,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: error,
      );
    }
  }
}

final reportProjectSelectorProvider =
    StateNotifierProvider.autoDispose<
      ReportProjectSelectorController,
      ReportProjectSelectorState
    >((ref) {
      final workspaceId = ref.watch(activeWorkspaceIdProvider) ?? '';
      final repository = ref.watch(projectRepositoryProvider);
      final controller = ReportProjectSelectorController(
        loadActivePage: ({cursor}) =>
            repository.fetchProjectsPage(workspaceId, cursor: cursor),
        loadArchivedPage: ({cursor}) =>
            repository.fetchArchivedProjectsPage(workspaceId, cursor: cursor),
      );
      if (workspaceId.isNotEmpty) {
        unawaited(controller.loadInitial());
      }
      return controller;
    });
