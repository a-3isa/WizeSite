import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';
import 'package:buildtrack_app/features/reports/presentation/screens/entity_aggregation_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PDF export failures are sanitized before display', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: EntityAggregationDetailScreen(
            summary: EntitySummary(
              entityId: 'supplier_1',
              entityName: 'Steel Supplier',
              entityType: 'supplier',
              totalExpenses: 100,
              transactionCount: 1,
            ),
            onExportPdf: (context, ref, summary) async {
              throw StateError('raw pdf secret');
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.picture_as_pdf_outlined));
    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('raw pdf secret'), findsNothing);
  });
}
