import 'dart:async';

import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/widgets/app_bottom_nav_shell.dart';
import 'package:buildtrack_app/features/add/presentation/screens/add_entry_screen.dart';
import 'package:buildtrack_app/features/add/presentation/screens/add_hub_screen.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/features_screen.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/login_screen.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/signup_screen.dart';
import 'package:buildtrack_app/features/auth/presentation/screens/splash_screen.dart';
import 'package:buildtrack_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:buildtrack_app/features/expenses/presentation/screens/add_expense_screen.dart';
import 'package:buildtrack_app/features/expenses/presentation/screens/expense_detail_screen.dart';
import 'package:buildtrack_app/features/expenses/presentation/screens/expenses_screen.dart';
import 'package:buildtrack_app/features/expenses/presentation/screens/voice_expense_screen.dart';
import 'package:buildtrack_app/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:buildtrack_app/features/payments/presentation/screens/add_payment_screen.dart';
import 'package:buildtrack_app/features/payments/presentation/screens/payment_detail_screen.dart';
import 'package:buildtrack_app/features/payments/presentation/screens/payments_screen.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/create_project_screen.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/project_detail_screen.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/archived_projects_screen.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/reports/presentation/screens/reports_screen.dart';
import 'package:buildtrack_app/features/settings/presentation/screens/profile_edit_screen.dart';
import 'package:buildtrack_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:buildtrack_app/features/settings/presentation/screens/team_management_screen.dart';
import 'package:buildtrack_app/features/subscription/presentation/screens/limit_reached_screen.dart';
import 'package:buildtrack_app/features/subscription/presentation/screens/manage_subscription_screen.dart';
import 'package:buildtrack_app/features/subscription/presentation/screens/plans_screen.dart';
import 'package:buildtrack_app/features/subscription/presentation/screens/subscription_success_screen.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/add_worker_entry_screen.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/add_worker_screen.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/worker_detail_screen.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final rootRouteObserver = RouteObserver<ModalRoute<dynamic>>();
  final dashboardRouteObserver = RouteObserver<ModalRoute<dynamic>>();
  final addRouteObserver = RouteObserver<ModalRoute<dynamic>>();
  final projectsRouteObserver = RouteObserver<ModalRoute<dynamic>>();
  final refresh = _RouterRefreshNotifier(auth.authStateChanges());
  ref.onDispose(refresh.dispose);
  ref.listen<String?>(
    activeWorkspaceIdProvider,
    (previous, next) => refresh.refresh(),
  );
  ref.listen<String?>(
    activeUserIdProvider,
    (previous, next) => refresh.refresh(),
  );

  return GoRouter(
    initialLocation: AppRoutes.root,
    refreshListenable: refresh,
    observers: [rootRouteObserver],
    redirect: (context, state) {
      final location = state.uri.path;
      final isSignedIn = auth.currentUser != null;
      final workspaceId = ref.read(activeWorkspaceIdProvider);
      final userId = ref.read(activeUserIdProvider);
      final hasWorkspace =
          userId != null &&
          userId.isNotEmpty &&
          workspaceId != null &&
          workspaceId.isNotEmpty;
      return resolveAppRedirect(
        location: location,
        isSignedIn: isSignedIn,
        hasWorkspace: hasWorkspace,
      );
    },
    routes: [
      GoRoute(
        path: AppRoutes.root,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.features,
        name: 'features',
        builder: (context, state) => const FeaturesScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        name: 'signup',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        name: 'forgotPassword',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.reports,
        name: 'reports',
        pageBuilder: (context, state) {
          final projectId = state.uri.queryParameters['projectId'];
          return smoothAppPage<void>(
            key: state.pageKey,
            child: ReportsScreen(projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        pageBuilder: (context, state) => smoothAppPage<void>(
          key: state.pageKey,
          child: const SettingsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.profileEdit,
        name: 'profileEdit',
        pageBuilder: (context, state) => smoothAppPage<void>(
          key: state.pageKey,
          child: const ProfileEditScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.teamManagement,
        name: 'teamManagement',
        pageBuilder: (context, state) => smoothAppPage<void>(
          key: state.pageKey,
          child: const TeamManagementScreen(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppBottomNavShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            observers: [dashboardRouteObserver],
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                name: 'dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [addRouteObserver],
            routes: [
              GoRoute(
                path: AppRoutes.add,
                name: 'add',
                builder: (context, state) => const AddHubScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [projectsRouteObserver],
            routes: [
              GoRoute(
                path: AppRoutes.projects,
                name: 'projects',
                builder: (context, state) => const ProjectsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.createProject,
        name: 'createProject',
        pageBuilder: (context, state) => smoothAppPage<void>(
          key: state.pageKey,
          child: const CreateProjectScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.projectEdit,
        name: 'projectEdit',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return smoothAppPage<void>(
            key: state.pageKey,
            child: CreateProjectScreen(projectId: id),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.projectDetail,
        name: 'projectDetail',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return smoothAppPage<void>(
            key: state.pageKey,
            child: ProjectDetailScreen(projectId: id),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.archivedProjects,
        name: 'archivedProjects',
        pageBuilder: (context, state) => smoothAppPage<void>(
          key: state.pageKey,
          child: const ArchivedProjectsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.projectExpenses,
        name: 'projectExpenses',
        pageBuilder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          return smoothAppPage<void>(
            key: state.pageKey,
            child: ExpensesScreen(projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.addEntry,
        name: 'addEntry',
        pageBuilder: (context, state) {
          final tabParam = state.uri.queryParameters['tab'];
          final initialTab = int.tryParse(tabParam ?? '0') ?? 0;
          return smoothAppPage<void>(
            key: state.pageKey,
            child: AddEntryScreen(initialTab: initialTab),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.addExpense,
        name: 'addExpense',
        pageBuilder: (context, state) {
          final projectId = state.uri.queryParameters['projectId'];
          return smoothAppPage<void>(
            key: state.pageKey,
            child: AddExpenseScreen(projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.expenseDetail,
        name: 'expenseDetail',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final projectId = state.uri.queryParameters['projectId'];
          return smoothAppPage<void>(
            key: state.pageKey,
            child: ExpenseDetailScreen(expenseId: id, projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.expenseEdit,
        name: 'expenseEdit',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final projectId = state.uri.queryParameters['projectId'];
          return smoothAppPage<void>(
            key: state.pageKey,
            child: AddExpenseScreen(expenseId: id, projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.voiceExpense,
        name: 'voiceExpense',
        pageBuilder: (context, state) => smoothAppPage<void>(
          key: state.pageKey,
          child: const VoiceExpenseScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.payments,
        name: 'payments',
        pageBuilder: (context, state) {
          final projectId = state.uri.queryParameters['projectId'];
          return smoothAppPage<void>(
            key: state.pageKey,
            child: PaymentsScreen(projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.addPayment,
        name: 'addPayment',
        pageBuilder: (context, state) {
          final projectId = state.uri.queryParameters['projectId'];
          return smoothAppPage<void>(
            key: state.pageKey,
            child: AddPaymentScreen(projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.paymentDetail,
        name: 'paymentDetail',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return smoothAppPage<void>(
            key: state.pageKey,
            child: PaymentDetailScreen(paymentId: id),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.paymentEdit,
        name: 'paymentEdit',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return smoothAppPage<void>(
            key: state.pageKey,
            child: AddPaymentScreen(paymentId: id),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.workers,
        name: 'workers',
        pageBuilder: (context, state) => smoothAppPage<void>(
          key: state.pageKey,
          child: const WorkersScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.workerDetail,
        name: 'workerDetail',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return smoothAppPage<void>(
            key: state.pageKey,
            child: WorkerDetailScreen(workerId: id),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.workerEdit,
        name: 'workerEdit',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return smoothAppPage<void>(
            key: state.pageKey,
            child: AddWorkerScreen(workerId: id),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.addWorker,
        name: 'addWorker',
        pageBuilder: (context, state) => smoothAppPage<void>(
          key: state.pageKey,
          child: const AddWorkerScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.workerEntry,
        name: 'workerEntry',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final extra = state.extra;
          String? entryId;
          if (extra is Map<String, dynamic>) {
            entryId = extra['entryId'] as String?;
          }
          final projectId = state.uri.queryParameters['projectId'];
          return smoothAppPage<void>(
            key: state.pageKey,
            child: AddWorkerEntryScreen(
              workerId: id,
              entryId: entryId,
              projectId: projectId,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        pageBuilder: (context, state) => smoothAppPage<void>(
          key: state.pageKey,
          child: const NotificationsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.subscriptionPlans,
        name: 'subscriptionPlans',
        pageBuilder: (context, state) =>
            smoothAppPage<void>(key: state.pageKey, child: const PlansScreen()),
      ),
      GoRoute(
        path: AppRoutes.subscriptionLimit,
        name: 'subscriptionLimit',
        pageBuilder: (context, state) {
          final limitType = state.uri.queryParameters['limit'] ?? 'generic';
          return smoothAppPage<void>(
            key: state.pageKey,
            child: LimitReachedScreen(limitType: limitType),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.subscriptionManage,
        name: 'subscriptionManage',
        pageBuilder: (context, state) => smoothAppPage<void>(
          key: state.pageKey,
          child: const ManageSubscriptionScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.subscriptionSuccess,
        name: 'subscriptionSuccess',
        pageBuilder: (context, state) => smoothAppPage<void>(
          key: state.pageKey,
          child: const SubscriptionSuccessScreen(),
        ),
      ),
    ],
  );
});

CustomTransitionPage<T> smoothAppPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 160),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.035, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

String? resolveAppRedirect({
  required String location,
  required bool isSignedIn,
  required bool hasWorkspace,
}) {
  final isSplash = location == AppRoutes.root;
  final isAuthRoute =
      location == AppRoutes.login ||
      location == AppRoutes.signup ||
      location == AppRoutes.forgotPassword;
  final isPublicDiscovery =
      location == AppRoutes.features || location == AppRoutes.onboarding;
  final isPublicRoute = isSplash || isAuthRoute || isPublicDiscovery;

  if (!isSignedIn) {
    if (!isPublicRoute) {
      return AppRoutes.features;
    }
    return null;
  }

  if (isAuthRoute) {
    if (hasWorkspace) {
      return AppRoutes.dashboard;
    }
    return AppRoutes.root;
  }

  if (hasWorkspace && isPublicDiscovery) {
    return AppRoutes.dashboard;
  }

  if (!hasWorkspace && !isSplash && !isPublicDiscovery) {
    return AppRoutes.root;
  }

  return null;
}

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  void refresh() {
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
