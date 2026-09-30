import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/payments/presentation/screens/add_payment_screen.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/subscription/domain/entitlement_guard_service.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_repository.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_quota_repository.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakePaymentRepository implements PaymentRepository {
  var createCalls = 0;

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
    double? paidAmount,
    String? description,
    String? notes,
    String? entityId,
    String? entityName,
    String? entityType,
    double? projectTotalPaymentsBefore,
    List<Attachment>? attachments,
  }) async {
    createCalls += 1;
    return const MutationResult(queued: false);
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
    Object? cursor,
    int pageSize = 20,
  }) async {
    return const FirestorePage(items: [], hasMore: false);
  }

  @override
  Future<PaymentRecord?> getPayment(String paymentId) async {
    return null;
  }

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
    return const Stream.empty();
  }
}

class _FakeSubscriptionRepository implements SubscriptionRepository {
  @override
  Future<SubscriptionState> getSubscription(String workspaceId) async {
    return SubscriptionState.free();
  }

  @override
  Stream<SubscriptionState> watchSubscription(String workspaceId) {
    return Stream.value(SubscriptionState.free());
  }
}

class _FakeUsageQuotaRepository implements UsageQuotaRepository {
  @override
  Future<LimitCheckResult> checkLimit({
    required String workspaceId,
    required LimitType type,
    required int delta,
  }) async {
    return LimitCheckResult(
      allowed: false,
      limitType: type,
      current: 10,
      max: 10,
    );
  }

  @override
  Future<UsageSnapshot> getUsageSnapshot({
    required String workspaceId,
    required PlanLimits limits,
  }) async {
    return UsageSnapshot.empty(limits: limits);
  }

  @override
  Stream<UsageSnapshot> watchUsageSnapshot({
    required String workspaceId,
    required PlanLimits limits,
  }) {
    return Stream.value(UsageSnapshot.empty(limits: limits));
  }
}

Project _project({
  String id = 'project_1',
  String name = 'Project One',
  double? contractValue = 1000,
}) {
  return Project(
    id: id,
    workspaceId: 'workspace_1',
    name: name,
    clientName: 'Client',
    contractValue: contractValue,
    status: 'active',
    completionPercentage: 0,
    totalExpenses: 0,
    totalPayments: 0,
    netProfit: 0,
    isArchived: false,
  );
}

GoRouter _router() {
  return GoRouter(
    initialLocation: AppRoutes.addPaymentPath(projectId: 'project_1'),
    routes: [
      GoRoute(
        path: AppRoutes.addPayment,
        builder: (context, state) =>
            AddPaymentScreen(projectId: state.uri.queryParameters['projectId']),
      ),
      GoRoute(
        path: AppRoutes.subscriptionLimit,
        builder: (context, state) => Text(
          'limit:${state.uri.queryParameters['limit']}',
          textDirection: TextDirection.ltr,
        ),
      ),
      GoRoute(
        path: AppRoutes.projectDetail,
        builder: (context, state) =>
            const Text('Project Detail', textDirection: TextDirection.ltr),
      ),
    ],
  );
}

void main() {
  testWidgets('contract-less projects are absent from the payment picker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
          paymentRepositoryProvider.overrideWithValue(_FakePaymentRepository()),
          projectsProvider.overrideWith(
            (ref) => Stream.value([
              _project(),
              _project(
                id: 'project_ledger',
                name: 'Ledger Only',
                contractValue: null,
              ),
            ]),
          ),
          entitlementGuardProvider.overrideWithValue(
            EntitlementGuardService(
              subscriptionRepository: _FakeSubscriptionRepository(),
              usageQuotaRepository: _FakeUsageQuotaRepository(),
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: _router(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('qa_add_payment_project')));
    await tester.pumpAndSettle();

    // Core invariant: a project with no Contract Value cannot hold payments,
    // so the invalid combination is unreachable rather than merely refused on
    // submit.
    expect(find.text('Project One'), findsWidgets);
    expect(find.text('Ledger Only'), findsNothing);
  });

  testWidgets(
    'AddPaymentScreen exposes description and payment status controls',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            activeUserIdProvider.overrideWith((ref) => 'user_1'),
            paymentRepositoryProvider.overrideWithValue(
              _FakePaymentRepository(),
            ),
            projectsProvider.overrideWith((ref) => Stream.value([_project()])),
            entitlementGuardProvider.overrideWithValue(
              EntitlementGuardService(
                subscriptionRepository: _FakeSubscriptionRepository(),
                usageQuotaRepository: _FakeUsageQuotaRepository(),
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: _router(),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('qa_add_payment_description')),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Payment status'), findsOneWidget);
    },
  );

  testWidgets('AddPaymentScreen localizes attachment controls in Arabic', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
          paymentRepositoryProvider.overrideWithValue(_FakePaymentRepository()),
          projectsProvider.overrideWith((ref) => Stream.value([_project()])),
          entitlementGuardProvider.overrideWithValue(
            EntitlementGuardService(
              subscriptionRepository: _FakeSubscriptionRepository(),
              usageQuotaRepository: _FakeUsageQuotaRepository(),
            ),
          ),
        ],
        child: MaterialApp.router(
          locale: const Locale('ar'),
          routerConfig: _router(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('qa_add_payment_pick_attachments')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('المرفقات'), findsOneWidget);
    expect(find.text('اختيار المرفقات'), findsOneWidget);
    expect(find.text('Attachments'), findsNothing);
    expect(find.text('Select attachments'), findsNothing);
  });

  testWidgets('AddPaymentScreen blocks create when monthly payment quota is hit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final paymentRepository = _FakePaymentRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
          paymentRepositoryProvider.overrideWithValue(paymentRepository),
          projectsProvider.overrideWith((ref) => Stream.value([_project()])),
          entitlementGuardProvider.overrideWithValue(
            EntitlementGuardService(
              subscriptionRepository: _FakeSubscriptionRepository(),
              usageQuotaRepository: _FakeUsageQuotaRepository(),
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: _router(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('qa_add_payment_amount')),
      '100',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('qa_add_payment_save')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Save Payment'), findsOneWidget);
    await tester.tap(find.byKey(const Key('qa_add_payment_save')));
    await tester.pumpAndSettle();

    expect(paymentRepository.createCalls, 0);
    expect(find.text('limit:paymentsPerMonth'), findsOneWidget);
  });
}
