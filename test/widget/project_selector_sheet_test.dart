import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:buildtrack_app/features/dashboard/presentation/widgets/project_selector_sheet.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Project _project(String id, String name) => Project(
  id: id,
  workspaceId: 'workspace_1',
  name: name,
  clientName: 'Owner',
  contractValue: 0,
  status: 'active',
  completionPercentage: 0,
  totalExpenses: 0,
  totalPayments: 0,
  netProfit: 0,
  isArchived: false,
);

/// Minimal host that mirrors how `_DashboardProjectSelector` opens the
/// sheet: a button that calls [showProjectSelectorSheet] with the given
/// projects and current selection.
Widget _host({
  required List<Project> projects,
  required String? selectedProjectId,
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            return ElevatedButton(
              key: const Key('qa_open_sheet'),
              onPressed: () => showProjectSelectorSheet(
                context,
                ref,
                projects: projects,
                selectedProjectId: selectedProjectId,
              ),
              child: const Text('Open'),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'project selector sheet lists All Projects then every project, and '
    'selecting one updates the provider',
    (tester) async {
      final projects = [_project('p1', 'Villa Project'), _project('p2', 'Tower B')];
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    key: const Key('qa_open_sheet'),
                    onPressed: () => showProjectSelectorSheet(
                      context,
                      ref,
                      projects: projects,
                      selectedProjectId: null,
                    ),
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('qa_open_sheet')));
      await tester.pumpAndSettle();

      // No search box below the 6-project threshold.
      expect(find.byKey(const Key('qa_project_selector_search')), findsNothing);

      expect(find.text('All Projects'), findsOneWidget);
      expect(find.text('Villa Project'), findsOneWidget);
      expect(find.text('Tower B'), findsOneWidget);

      await tester.tap(find.text('Tower B'));
      await tester.pumpAndSettle();

      expect(container.read(selectedDashboardProjectIdProvider), 'p2');
      // Sheet closed after selection.
      expect(find.text('Villa Project'), findsNothing);
    },
  );

  testWidgets(
    'search box appears with more than 6 projects and filters live',
    (tester) async {
      final projects = List.generate(
        8,
        (i) => _project('p$i', 'Project ${i + 1}'),
      );

      await tester.pumpWidget(
        _host(projects: projects, selectedProjectId: null),
      );

      await tester.tap(find.byKey(const Key('qa_open_sheet')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('qa_project_selector_search')),
        findsOneWidget,
      );
      expect(find.text('Project 1'), findsOneWidget);
      expect(find.text('Project 8'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('qa_project_selector_search')),
        'Project 8',
      );
      await tester.pumpAndSettle();

      // The typed text now appears twice: once in the search field itself,
      // once in the matching project tile.
      expect(find.text('Project 8'), findsNWidgets(2));
      expect(find.text('Project 1'), findsNothing);
      // "All Projects" is hidden once a search query narrows the list.
      expect(find.text('All Projects'), findsNothing);
    },
  );
}
