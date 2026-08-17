import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/payments/presentation/screens/add_payment_screen.dart';
import 'package:buildtrack_app/features/payments/presentation/screens/payment_detail_screen.dart';
import 'package:buildtrack_app/features/payments/presentation/screens/payments_screen.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakePaymentRepository implements PaymentRepository {
  _FakePaymentRepository(this.payment);

  final PaymentRecord payment;

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
    String? paymentStatus,
    String? description,
    String? notes,
    String? entityId,
    String? entityName,
    String? entityType,
    double? projectTotalPaymentsBefore,
    List<Attachment>? attachments,
  }) async {
    return const MutationResult();
  }

  @override
  Future<FirestorePage<PaymentRecord>> fetchPaymentsPage(
    String workspaceId, {
    String? projectId,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
    cursor,
    int pageSize = 20,
  }) async {
    return FirestorePage<PaymentRecord>(
      items: projectId == null || projectId == payment.projectId
          ? [payment]
          : const [],
      hasMore: false,
    );
  }

  @override
  Future<PaymentRecord?> getPayment(String paymentId) async => payment;

  @override
  Future<void> updatePayment({
    required String paymentId,
    required double amount,
    required DateTime date,
    required String paymentMethod,
    String? paymentStatus,
    String? description,
    String? notes,
    String? entityId,
    String? entityName,
    String? entityType,
    List<Attachment>? attachments,
  }) async {}

  @override
  Stream<List<PaymentRecord>> watchPayments(
    String workspaceId, {
    String? projectId,
  }) {
    return Stream.value(
      projectId == null || projectId == payment.projectId
          ? [payment]
          : const [],
    );
  }
}

class _FakeProjectRepository implements ProjectRepository {
  @override
  Future<bool> hasAnyPayment(String projectId) async => false;

  @override
  Future<void> archiveProject(String projectId) async {}

  @override
  Future<MutationResult> createProject({
    required String workspaceId,
    required String userId,
    required String name,
    required String clientName,
    double? contractValue,
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
    cursor,
    int pageSize = 20,
  }) async {
    return const FirestorePage<Project>(items: [], hasMore: false);
  }

  @override
  Future<FirestorePage<Project>> fetchProjectsPage(
    String workspaceId, {
    cursor,
    int pageSize = 20,
  }) async {
    return const FirestorePage<Project>(items: [], hasMore: false);
  }

  @override
  Future<Project?> getProject(String projectId) async => _project();

  @override
  Future<void> unarchiveProject(String projectId) async {}

  @override
  Future<void> updateProject({
    required String projectId,
    required String name,
    required String clientName,
    double? contractValue,
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
    return Stream.value([_project()]);
  }

  @override
  Stream<List<Project>> watchArchivedProjects(String workspaceId) {
    return const Stream<List<Project>>.empty();
  }

  @override
  Stream<Project?> watchProject(String projectId) {
    return Stream.value(_project());
  }

  @override
  Stream<List<Project>> watchProjects(String workspaceId) {
    return Stream.value([_project()]);
  }
}

Project _project() {
  return const Project(
    id: 'project_1',
    workspaceId: 'workspace_test',
    name: 'Project 1',
    clientName: 'Client 1',
    contractValue: 1000,
    status: 'active',
    completionPercentage: 25,
    totalExpenses: 200,
    totalPayments: 400,
    netProfit: 200,
    isArchived: false,
  );
}

PaymentRecord _payment() {
  return PaymentRecord(
    id: 'pay_1',
    workspaceId: 'workspace_test',
    projectId: 'project_1',
    amount: 100,
    date: DateTime(2026, 3, 26),
    paymentMethod: 'cash',
    paymentStatus: 'paid',
    description: 'invoice advance',
    notes: '',
    entityName: 'Steel Supplier',
    entityType: 'supplier',
    attachments: const [],
    isArchived: false,
  );
}

Widget _appWithRouter(GoRouter router, PaymentRepository paymentRepository) {
  return ProviderScope(
    overrides: [
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_test'),
      projectRepositoryProvider.overrideWithValue(_FakeProjectRepository()),
      paymentRepositoryProvider.overrideWithValue(paymentRepository),
      projectsProvider.overrideWith((ref) => Stream.value([_project()])),
      currentUserSettingsProvider.overrideWith(
        (ref) => Stream.value(UserSettings.defaults(userId: 'user_1')),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  testWidgets('payments list navigation preserves project context', (
    tester,
  ) async {
    final paymentRepository = _FakePaymentRepository(_payment());
    final router = GoRouter(
      initialLocation: AppRoutes.paymentsPath(projectId: 'project_1'),
      routes: [
        GoRoute(
          path: AppRoutes.payments,
          builder: (context, state) =>
              PaymentsScreen(projectId: state.uri.queryParameters['projectId']),
        ),
        GoRoute(
          path: AppRoutes.paymentDetail,
          builder: (context, state) => Scaffold(
            body: Text(
              'detail:${state.uri.queryParameters['projectId'] ?? ''}',
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.addPayment,
          builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
        ),
      ],
    );

    await tester.pumpWidget(_appWithRouter(router, paymentRepository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('detail:project_1'), findsOneWidget);
  });

  testWidgets('payment detail edit route preserves project context', (
    tester,
  ) async {
    final paymentRepository = _FakePaymentRepository(_payment());
    final router = GoRouter(
      initialLocation: AppRoutes.paymentDetailPath(
        'pay_1',
        projectId: 'project_1',
      ),
      routes: [
        GoRoute(
          path: AppRoutes.paymentDetail,
          builder: (context, state) => PaymentDetailScreen(
            paymentId: state.pathParameters['id']!,
            projectId: state.uri.queryParameters['projectId'],
          ),
        ),
        GoRoute(
          path: AppRoutes.paymentEdit,
          builder: (context, state) => Scaffold(
            body: Text('edit:${state.uri.queryParameters['projectId'] ?? ''}'),
          ),
        ),
        GoRoute(
          path: AppRoutes.payments,
          builder: (context, state) => Scaffold(
            body: Text(
              'payments:${state.uri.queryParameters['projectId'] ?? ''}',
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(_appWithRouter(router, paymentRepository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('edit:project_1'), findsOneWidget);
  });

  testWidgets('payment detail back fallback returns to project payments', (
    tester,
  ) async {
    final paymentRepository = _FakePaymentRepository(_payment());
    final router = GoRouter(
      initialLocation: AppRoutes.paymentDetailPath(
        'pay_1',
        projectId: 'project_1',
      ),
      routes: [
        GoRoute(
          path: AppRoutes.paymentDetail,
          builder: (context, state) => PaymentDetailScreen(
            paymentId: state.pathParameters['id']!,
            projectId: state.uri.queryParameters['projectId'],
          ),
        ),
        GoRoute(
          path: AppRoutes.payments,
          builder: (context, state) => Scaffold(
            body: Text(
              'payments:${state.uri.queryParameters['projectId'] ?? ''}',
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(_appWithRouter(router, paymentRepository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();

    expect(find.text('payments:project_1'), findsOneWidget);
  });

  testWidgets('add payment back fallback returns to project payments', (
    tester,
  ) async {
    final paymentRepository = _FakePaymentRepository(_payment());
    final router = GoRouter(
      initialLocation: AppRoutes.addPaymentPath(projectId: 'project_1'),
      routes: [
        GoRoute(
          path: AppRoutes.addPayment,
          builder: (context, state) => AddPaymentScreen(
            projectId: state.uri.queryParameters['projectId'],
          ),
        ),
        GoRoute(
          path: AppRoutes.payments,
          builder: (context, state) => Scaffold(
            body: Text(
              'payments:${state.uri.queryParameters['projectId'] ?? ''}',
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(_appWithRouter(router, paymentRepository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();

    expect(find.text('payments:project_1'), findsOneWidget);
  });

  testWidgets('edit payment back fallback returns to project payments', (
    tester,
  ) async {
    final paymentRepository = _FakePaymentRepository(_payment());
    final router = GoRouter(
      initialLocation: AppRoutes.paymentEditPath(
        'pay_1',
        projectId: 'project_1',
      ),
      routes: [
        GoRoute(
          path: AppRoutes.paymentEdit,
          builder: (context, state) => AddPaymentScreen(
            paymentId: state.pathParameters['id'],
            projectId: state.uri.queryParameters['projectId'],
          ),
        ),
        GoRoute(
          path: AppRoutes.payments,
          builder: (context, state) => Scaffold(
            body: Text(
              'payments:${state.uri.queryParameters['projectId'] ?? ''}',
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(_appWithRouter(router, paymentRepository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();

    expect(find.text('payments:project_1'), findsOneWidget);
  });
}
