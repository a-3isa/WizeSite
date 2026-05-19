import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/session_restore_service.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/voice_expense/data/voice_expense_repository.dart';
import 'package:buildtrack_app/features/voice_expense/domain/voice_expense_models.dart';
import 'package:buildtrack_app/features/voice_expense/presentation/screens/voice_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockSessionRestoreService extends Mock
    implements SessionRestoreService {}

class _MockVoiceExpenseRepository extends Mock
    implements VoiceExpenseRepository {}

class _FakeProjectRepository implements ProjectRepository {
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
    throw UnimplementedError();
  }

  @override
  Future<void> deleteProject(String projectId) async {}

  @override
  Future<FirestorePage<Project>> fetchArchivedProjectsPage(
    String workspaceId, {
    cursor,
    int pageSize = 20,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<FirestorePage<Project>> fetchProjectsPage(
    String workspaceId, {
    cursor,
    int pageSize = 20,
  }) async {
    throw UnimplementedError();
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
    return const Stream.empty();
  }

  @override
  Stream<List<Project>> watchArchivedProjects(String workspaceId) {
    return const Stream.empty();
  }

  @override
  Stream<Project?> watchProject(String projectId) {
    return const Stream.empty();
  }

  @override
  Stream<List<Project>> watchProjects(String workspaceId) {
    return const Stream.empty();
  }
}

GoRouter _router(Widget child) {
  return GoRouter(
    initialLocation: '/review',
    routes: [
      GoRoute(path: '/review', builder: (context, state) => child),
      GoRoute(
        path: '/project/:projectId/expenses',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Project Expenses Screen')),
        ),
      ),
    ],
  );
}

VoiceExpenseParseResponse _response() {
  return const VoiceExpenseParseResponse(
    transcript: 'cement purchase',
    parsed: VoiceParsedExpense(
      amount: 1250,
      currency: 'EGP',
      category: 'materials',
      matchedProjectId: 'project_1',
      matchedProjectName: 'Tower A',
      note: 'cement',
    ),
    confidence: VoiceConfidenceScores(
      amount: 0.9,
      category: 0.8,
      project: 0.95,
      overall: 0.88,
    ),
    source: 'rules',
    needsConfirmation: true,
    storagePath: 'voice/path.m4a',
  );
}

void main() {
  testWidgets(
    'VoiceReviewScreen restores workspace before saving confirmed expense',
    (tester) async {
      final sessionRestoreService = _MockSessionRestoreService();
      final voiceRepository = _MockVoiceExpenseRepository();

      when(() => sessionRestoreService.restore()).thenAnswer(
        (_) async => const SessionRestoreResult(
          userId: 'user_1',
          workspaceId: 'workspace_1',
        ),
      );
      when(
        () => voiceRepository.saveConfirmedVoiceExpense(
          workspaceId: any(named: 'workspaceId'),
          projectId: any(named: 'projectId'),
          projectName: any(named: 'projectName'),
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
          category: any(named: 'category'),
          notes: any(named: 'notes'),
          transcript: any(named: 'transcript'),
          source: any(named: 'source'),
          storagePath: any(named: 'storagePath'),
          date: any(named: 'date'),
        ),
      ).thenAnswer((_) async => 'expense_1');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => null),
            activeUserIdProvider.overrideWith((ref) => null),
            sessionRestoreServiceProvider.overrideWithValue(
              sessionRestoreService,
            ),
            voiceExpenseRepositoryProvider.overrideWithValue(voiceRepository),
            projectRepositoryProvider.overrideWithValue(_FakeProjectRepository()),
            currentUserSettingsProvider.overrideWith(
              (ref) => Stream.value(
                UserSettings.defaults(userId: 'user_1', email: 'u@test.com'),
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: _router(
              VoiceReviewScreen(
                response: _response(),
                projects: const [
                  VoiceProjectOption(id: 'project_1', name: 'Tower A'),
                ],
              ),
            ),
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
      expect(find.text('Review Voice Expense'), findsOneWidget);
      final confirmButton = find.text('Confirm & Save');
      await tester.scrollUntilVisible(
        confirmButton,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(confirmButton, findsOneWidget);
      await tester.tap(confirmButton);
      await tester.pump();
      await tester.pumpAndSettle();

      verify(() => sessionRestoreService.restore()).called(1);
      verify(
        () => voiceRepository.saveConfirmedVoiceExpense(
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          projectName: 'Tower A',
          amount: 1250,
          currency: 'EGP',
          category: 'materials',
          notes: 'cement',
          transcript: 'cement purchase',
          source: 'rules',
          storagePath: 'voice/path.m4a',
          date: any(named: 'date'),
        ),
      ).called(1);
      expect(find.text('Project Expenses Screen'), findsOneWidget);
    },
  );
}
