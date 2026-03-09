import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/widgets/app_bottom_nav_shell.dart';
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
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/reports/presentation/screens/reports_screen.dart';
import 'package:buildtrack_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:buildtrack_app/features/subscription/presentation/screens/limit_reached_screen.dart';
import 'package:buildtrack_app/features/subscription/presentation/screens/manage_subscription_screen.dart';
import 'package:buildtrack_app/features/subscription/presentation/screens/plans_screen.dart';
import 'package:buildtrack_app/features/subscription/presentation/screens/subscription_success_screen.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/add_worker_entry_screen.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/add_worker_screen.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/worker_detail_screen.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.root,
    routes: [
      GoRoute(
        path: AppRoutes.root,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.features,
        builder: (context, state) => const FeaturesScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppBottomNavShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.projects,
                builder: (context, state) => const ProjectsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.add,
                builder: (context, state) => const AddHubScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.reports,
                builder: (context, state) => const ReportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.createProject,
        builder: (context, state) => const CreateProjectScreen(),
      ),
      GoRoute(
        path: AppRoutes.projectEdit,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return CreateProjectScreen(projectId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.projectDetail,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return ProjectDetailScreen(projectId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.expenses,
        builder: (context, state) => const ExpensesScreen(),
      ),
      GoRoute(
        path: AppRoutes.addExpense,
        builder: (context, state) => const AddExpenseScreen(),
      ),
      GoRoute(
        path: AppRoutes.expenseDetail,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return ExpenseDetailScreen(expenseId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.expenseEdit,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return AddExpenseScreen(expenseId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.voiceExpense,
        builder: (context, state) => const VoiceExpenseScreen(),
      ),
      GoRoute(
        path: AppRoutes.payments,
        builder: (context, state) => const PaymentsScreen(),
      ),
      GoRoute(
        path: AppRoutes.addPayment,
        builder: (context, state) => const AddPaymentScreen(),
      ),
      GoRoute(
        path: AppRoutes.paymentDetail,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return PaymentDetailScreen(paymentId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.paymentEdit,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return AddPaymentScreen(paymentId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.workers,
        builder: (context, state) => const WorkersScreen(),
      ),
      GoRoute(
        path: AppRoutes.workerDetail,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return WorkerDetailScreen(workerId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.workerEdit,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return AddWorkerScreen(workerId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.addWorker,
        builder: (context, state) => const AddWorkerScreen(),
      ),
      GoRoute(
        path: AppRoutes.workerEntry,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final extra = state.extra;
          String? entryId;
          if (extra is Map<String, dynamic>) {
            entryId = extra['entryId'] as String?;
          }
          return AddWorkerEntryScreen(workerId: id, entryId: entryId);
        },
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.subscriptionPlans,
        builder: (context, state) => const PlansScreen(),
      ),
      GoRoute(
        path: AppRoutes.subscriptionLimit,
        builder: (context, state) {
          final limitType = state.uri.queryParameters['limit'] ?? 'generic';
          return LimitReachedScreen(limitType: limitType);
        },
      ),
      GoRoute(
        path: AppRoutes.subscriptionManage,
        builder: (context, state) => const ManageSubscriptionScreen(),
      ),
      GoRoute(
        path: AppRoutes.subscriptionSuccess,
        builder: (context, state) => const SubscriptionSuccessScreen(),
      ),
    ],
  );
});
