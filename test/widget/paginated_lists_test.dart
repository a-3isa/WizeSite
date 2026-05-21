import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/payments/presentation/screens/payments_screen.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository({
    required List<Project> activeProjects,
    required this.firstPage,
    this.secondPage,
  }) : _activeProjects = activeProjects;

  final List<Project> _activeProjects;
  final FirestorePage<Project> firstPage;
  final FirestorePage<Project>? secondPage;
  int _fetchCalls = 0;

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
    if (_fetchCalls == 0 || secondPage == null) {
      _fetchCalls += 1;
      return firstPage;
    }
    _fetchCalls += 1;
    return secondPage!;
  }

  @override
  Future<Project?> getProject(String projectId) async {
    return _activeProjects.firstWhere((project) => project.id == projectId);
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
    return Stream.value(_activeProjects);
  }

  @override
  Stream<List<Project>> watchArchivedProjects(String workspaceId) {
    return const Stream<List<Project>>.empty();
  }

  @override
  Stream<Project?> watchProject(String projectId) {
    return Stream.value(
      _activeProjects.firstWhere((project) => project.id == projectId),
    );
  }

  @override
  Stream<List<Project>> watchProjects(String workspaceId) {
    return Stream.value(_activeProjects);
  }
}

class _FakePaymentRepository implements PaymentRepository {
  _FakePaymentRepository(this.paymentsByProject);

  final Map<String?, List<PaymentRecord>> paymentsByProject;
  final List<String?> requestedProjectIds = [];

  @override
  Future<MutationResult> archivePayment(String paymentId) async {
    return const MutationResult();
  }

  @override
  Future<MutationResult> createPayment({
    required String workspaceId,
    required String userId,
    required String projectId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? notes,
    double? projectTotalPaymentsBefore,
  }) async {
    return const MutationResult();
  }

  @override
  Future<FirestorePage<PaymentRecord>> fetchPaymentsPage(
    String workspaceId, {
    String? projectId,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    requestedProjectIds.add(projectId);
    return FirestorePage<PaymentRecord>(
      items: paymentsByProject[projectId] ?? const [],
      hasMore: false,
    );
  }

  @override
  Future<PaymentRecord?> getPayment(String paymentId) async {
    return paymentsByProject.values
        .expand((items) => items)
        .firstWhere((payment) => payment.id == paymentId);
  }

  @override
  Future<void> updatePayment({
    required String paymentId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? notes,
  }) async {}

  @override
  Stream<List<PaymentRecord>> watchPayments(
    String workspaceId, {
    String? projectId,
  }) {
    return Stream.value(paymentsByProject[projectId] ?? const []);
  }
}

Project _project(int index) {
  return Project(
    id: 'project_$index',
    workspaceId: 'workspace_test',
    name: 'Project $index',
    clientName: 'Client $index',
    contractValue: 1000 + index.toDouble(),
    status: 'active',
    completionPercentage: 25,
    totalExpenses: 200,
    totalPayments: 400,
    netProfit: 200,
    isArchived: false,
  );
}

PaymentRecord _payment({
  required String id,
  required String projectId,
  required double amount,
}) {
  return PaymentRecord(
    id: id,
    workspaceId: 'workspace_test',
    projectId: projectId,
    amount: amount,
    date: DateTime(2026, 3, 26),
    paymentMethod: 'cash',
    notes: '',
    isArchived: false,
  );
}

GoRouter _paymentsRouter() {
  return GoRouter(
    initialLocation: '/payments',
    routes: [
      GoRoute(
        path: '/payments',
        builder: (context, state) =>
            PaymentsScreen(projectId: state.uri.queryParameters['projectId']),
      ),
      GoRoute(
        path: '/payment/:id',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/add-payment',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );
}

GoRouter _projectsRouter() {
  return GoRouter(
    initialLocation: '/projects',
    routes: [
      GoRoute(
        path: '/projects',
        builder: (context, state) => const ProjectsScreen(),
      ),
      GoRoute(
        path: '/project/:id',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/projects/archived',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/projects/create',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );
}

void main() {
  testWidgets('PaymentsScreen applies the selected project filter', (
    tester,
  ) async {
    final fakeProjectRepository = _FakeProjectRepository(
      activeProjects: [_project(1), _project(2)],
      firstPage: const FirestorePage<Project>(items: [], hasMore: false),
    );
    final fakePaymentRepository = _FakePaymentRepository({
      null: [
        _payment(id: 'pay_1', projectId: 'project_1', amount: 100),
        _payment(id: 'pay_2', projectId: 'project_2', amount: 200),
      ],
      'project_1': [_payment(id: 'pay_1', projectId: 'project_1', amount: 100)],
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_test'),
          projectRepositoryProvider.overrideWithValue(fakeProjectRepository),
          paymentRepositoryProvider.overrideWithValue(fakePaymentRepository),
        ],
        child: MaterialApp.router(routerConfig: _paymentsRouter()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('project_1'), findsOneWidget);
    expect(find.textContaining('project_2'), findsOneWidget);

    await tester.tap(find.byType(BelowDropdownField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project 1').last);
    await tester.pumpAndSettle();

    expect(fakePaymentRepository.requestedProjectIds, contains('project_1'));
    expect(find.textContaining('project_1'), findsOneWidget);
    expect(find.textContaining('project_2'), findsNothing);
  });

  testWidgets('ProjectsScreen loads the next page when scrolled', (
    tester,
  ) async {
    final firstBatch = List.generate(20, (index) => _project(index + 1));
    final secondBatch = List.generate(5, (index) => _project(index + 21));

    final fakeProjectRepository = _FakeProjectRepository(
      activeProjects: firstBatch,
      firstPage: FirestorePage<Project>(items: firstBatch, hasMore: true),
      secondPage: FirestorePage<Project>(items: secondBatch, hasMore: false),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_test'),
          projectRepositoryProvider.overrideWithValue(fakeProjectRepository),
          // Override so the cache-first path in _refresh() never short-circuits
          // pagination — the test must exercise the load-more fetch path.
          projectsProvider.overrideWith(
            (ref) => const Stream<List<Project>>.empty(),
          ),
        ],
        child: MaterialApp.router(routerConfig: _projectsRouter()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Project 25'), findsNothing);

    final scrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('Project 25'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Project 25'), findsOneWidget);
  });
}
