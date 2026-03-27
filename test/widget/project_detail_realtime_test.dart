import 'dart:async';

import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/project_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _RealtimeProjectRepository implements ProjectRepository {
  _RealtimeProjectRepository(this.controller);

  final StreamController<Project?> controller;

  @override
  Future<void> archiveProject(String projectId) async {}

  @override
  Future<MutationResult> createProject({
    required String workspaceId,
    required String userId,
    required String name,
    required String clientName,
    required double contractValue,
    required DateTime startDate,
    DateTime? expectedEndDate,
    String? location,
    String? description,
    double? budgetLimit,
    double completionPercentage = 0,
  }) async {
    return const MutationResult();
  }

  @override
  Future<void> deleteProject(String projectId) async {}

  @override
  Future<FirestorePage<Project>> fetchArchivedProjectsPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    return const FirestorePage<Project>(items: [], hasMore: false);
  }

  @override
  Future<FirestorePage<Project>> fetchProjectsPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    return const FirestorePage<Project>(items: [], hasMore: false);
  }

  @override
  Future<Project?> getProject(String projectId) async {
    return null;
  }

  @override
  Future<void> unarchiveProject(String projectId) async {}

  @override
  Future<void> updateProject({
    required String projectId,
    required String name,
    required String clientName,
    required double contractValue,
    required DateTime startDate,
    DateTime? expectedEndDate,
    String? location,
    String? description,
    double? budgetLimit,
    double? completionPercentage,
    String? status,
  }) async {}

  @override
  Stream<List<Project>> watchAllProjects(String workspaceId) {
    return const Stream<List<Project>>.empty();
  }

  @override
  Stream<List<Project>> watchArchivedProjects(String workspaceId) {
    return const Stream<List<Project>>.empty();
  }

  @override
  Stream<Project?> watchProject(String projectId) => controller.stream;

  @override
  Stream<List<Project>> watchProjects(String workspaceId) {
    return const Stream<List<Project>>.empty();
  }
}

Project _project({
  required String name,
  required String clientName,
  required double totalExpenses,
}) {
  return Project(
    id: 'project_1',
    workspaceId: 'workspace_test',
    name: name,
    clientName: clientName,
    contractValue: 10000,
    status: 'active',
    completionPercentage: 40,
    totalExpenses: totalExpenses,
    totalPayments: 8000,
    netProfit: 2000 - totalExpenses,
    isArchived: false,
  );
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/project/project_1',
    routes: [
      GoRoute(
        path: '/projects',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/project/:id',
        builder: (context, state) =>
            ProjectDetailScreen(projectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/project/:id/edit',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/project/:projectId/expenses',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/payments',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/workers',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/add-expense',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/add-payment',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/worker-entry/:id',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );
}

void main() {
  testWidgets('ProjectDetailScreen updates when the project stream changes', (
    tester,
  ) async {
    final controller = StreamController<Project?>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectRepositoryProvider.overrideWithValue(
            _RealtimeProjectRepository(controller),
          ),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );

    controller.add(
      _project(
        name: 'Project Alpha',
        clientName: 'Client One',
        totalExpenses: 1500,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Project Alpha'), findsOneWidget);
    expect(find.text('Client One'), findsOneWidget);
    expect(find.text('1500'), findsOneWidget);

    controller.add(
      _project(
        name: 'Project Beta',
        clientName: 'Client Two',
        totalExpenses: 3200,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Project Alpha'), findsNothing);
    expect(find.text('Client One'), findsNothing);
    expect(find.text('Project Beta'), findsOneWidget);
    expect(find.text('Client Two'), findsOneWidget);
    expect(find.text('3200'), findsOneWidget);
  });
}
