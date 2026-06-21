import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';
import 'package:buildtrack_app/features/reports/presentation/screens/entity_aggregation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('denies direct access for member role', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
          currentAccountingRoleProvider.overrideWith(
            (ref) => Stream.value(AccountingAccessRoleType.member),
          ),
          entityAggregationsProvider.overrideWith(
            (ref, workspaceId) => Stream.value([
              EntitySummary(
                entityId: 'supplier_1',
                entityName: 'Steel Supplier',
                entityType: 'supplier',
                totalExpenses: 100,
                transactionCount: 1,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: EntityAggregationScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.textContaining('permission to view financial reports'),
      findsOneWidget,
    );
    expect(find.text('Steel Supplier'), findsNothing);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
  });

  testWidgets('denies direct access when membership is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
          currentAccountingRoleProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
          entityAggregationsProvider.overrideWith(
            (ref, workspaceId) => Stream.value([
              EntitySummary(
                entityId: 'supplier_1',
                entityName: 'Steel Supplier',
                entityType: 'supplier',
                totalExpenses: 100,
                transactionCount: 1,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: EntityAggregationScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.textContaining('permission to view financial reports'),
      findsOneWidget,
    );
    expect(find.text('Steel Supplier'), findsNothing);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
  });

  testWidgets('filters entity aggregation rows by search text and type', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
          currentAccountingRoleProvider.overrideWith(
            (ref) => Stream.value(AccountingAccessRoleType.owner),
          ),
          entityAggregationsProvider.overrideWith(
            (ref, workspaceId) => Stream.value([
              EntitySummary(
                entityId: 'supplier_1',
                entityName: 'Steel Supplier',
                entityType: 'supplier',
                totalExpenses: 100,
                transactionCount: 1,
              ),
              EntitySummary(
                entityId: 'worker_1',
                entityName: 'Worker One',
                entityType: 'worker',
                totalExpenses: 75,
                transactionCount: 1,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: EntityAggregationScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Steel Supplier'), findsOneWidget);
    expect(find.text('Worker One'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('entity_aggregation_search')),
      'worker',
    );
    await tester.pumpAndSettle();

    expect(find.text('Steel Supplier'), findsNothing);
    expect(find.text('Worker One'), findsOneWidget);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('export failures are sanitized before display', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
          currentAccountingRoleProvider.overrideWith(
            (ref) => Stream.value(AccountingAccessRoleType.owner),
          ),
          entityAggregationsProvider.overrideWith(
            (ref, workspaceId) => Stream.value([
              EntitySummary(
                entityId: 'supplier_1',
                entityName: 'Steel Supplier',
                entityType: 'supplier',
                totalExpenses: 100,
                transactionCount: 1,
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: EntityAggregationScreen(
            onExportPdf:
                ({
                  required l10n,
                  required summaries,
                  required selectedType,
                  required currency,
                }) async {
                  throw StateError('raw summary secret');
                },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.picture_as_pdf_outlined));
    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('raw summary secret'), findsNothing);
  });
}
