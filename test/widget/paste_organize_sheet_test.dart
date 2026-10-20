import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/providers/connectivity_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/features/expenses/data/expense_text_organizer.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_proposal.dart';
import 'package:buildtrack_app/features/expenses/presentation/widgets/paste_organize_sheet.dart';
import 'package:buildtrack_app/features/voice_expense/data/voice_ai_disclosure_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _l10n = AppLocalizations(const Locale('en'));
const _reference =
    'فاتورة سباكه شهر 10\n100 جنيه حنفية 50 جنيه جلبه 90 جنيه ماسورة';

class _FakeOrganizer implements ExpenseTextOrganizer {
  _FakeOrganizer(this.respond);

  final Future<ExpenseTextOrganizeResult> Function(String text) respond;
  final calls = <String>[];

  @override
  Future<ExpenseTextOrganizeResult> organize({
    required String workspaceId,
    required String text,
    required String currency,
  }) {
    calls.add(text);
    return respond(text);
  }
}

class _FakeDisclosureStore implements VoiceAiDisclosureStore {
  _FakeDisclosureStore({this.accepted = true});

  bool accepted;

  @override
  bool get hasAccepted => accepted;

  @override
  Future<void> accept() async => accepted = true;
}

ExpenseTextOrganizeResult _result({List<ProposalItem>? items}) {
  return ExpenseTextOrganizeResult(
    text: _reference,
    source: 'llm',
    proposal: ExpenseProposal(
      title: 'سباكه شهر 10',
      items:
          items ??
          const [
            ProposalItem(name: 'حنفية', amount: 100),
            ProposalItem(name: 'جلبه', amount: 50),
            ProposalItem(name: 'ماسورة', amount: 90),
          ],
    ),
  );
}

class _Host extends ConsumerWidget {
  const _Host({required this.onResult});

  final void Function(ExpenseTextOrganizeResult?) onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: const Key('open'),
          onPressed: () async => onResult(
            await showPasteOrganizeSheet(
              context,
              workspaceId: 'ws_1',
              currency: 'EGP',
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

Future<List<ExpenseTextOrganizeResult?>> _pump(
  WidgetTester tester, {
  required _FakeOrganizer organizer,
  _FakeDisclosureStore? store,
  bool offline = false,
}) async {
  final results = <ExpenseTextOrganizeResult?>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        expenseTextOrganizerProvider.overrideWithValue(organizer),
        voiceAiDisclosureStoreProvider.overrideWithValue(
          store ?? _FakeDisclosureStore(),
        ),
        isOfflineProvider.overrideWithValue(offline),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: _Host(onResult: results.add),
      ),
    ),
  );
  await _open(tester);
  return results;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

FilledButton _organizeButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('qa_organize_ai')));

void main() {
  testWidgets('organize is disabled for empty text', (tester) async {
    await _pump(tester, organizer: _FakeOrganizer((_) async => _result()));
    expect(_organizeButton(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('qa_paste_text')), _reference);
    await tester.pump();
    expect(_organizeButton(tester).onPressed, isNotNull);
  });

  testWidgets('offline disables organize and says why', (tester) async {
    await _pump(
      tester,
      organizer: _FakeOrganizer((_) async => _result()),
      offline: true,
    );
    await tester.enterText(find.byKey(const Key('qa_paste_text')), _reference);
    await tester.pump();
    expect(_organizeButton(tester).onPressed, isNull);
    expect(find.text(_l10n.t('organizeOfflineHint')), findsOneWidget);
  });

  testWidgets('a successful organize returns the proposal to the caller', (
    tester,
  ) async {
    final organizer = _FakeOrganizer((_) async => _result());
    final results = await _pump(tester, organizer: organizer);
    await tester.enterText(find.byKey(const Key('qa_paste_text')), _reference);
    await tester.pump();
    await tester.tap(find.byKey(const Key('qa_organize_ai')));
    await tester.pumpAndSettle();

    expect(organizer.calls, [_reference]);
    expect(results.single!.proposal.items, hasLength(3));
    expect(find.byKey(const Key('qa_paste_text')), findsNothing);
  });

  testWidgets('progress shows while running; cancel keeps the text', (
    tester,
  ) async {
    final pending = Completer<ExpenseTextOrganizeResult>();
    final results = await _pump(
      tester,
      organizer: _FakeOrganizer((_) => pending.future),
    );
    await tester.enterText(find.byKey(const Key('qa_paste_text')), _reference);
    await tester.pump();
    await tester.tap(find.byKey(const Key('qa_organize_ai')));
    await tester.pump();
    expect(find.text(_l10n.t('organizing')), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa_organize_cancel')));
    await tester.pumpAndSettle();
    expect(results.single, isNull);

    pending.complete(_result());
    await tester.pumpAndSettle();
    await _open(tester);
    final field = tester.widget<TextField>(
      find.byKey(const Key('qa_paste_text')),
    );
    expect(field.controller!.text, _reference, reason: 'text survives cancel');
  });

  testWidgets('no items found keeps the sheet open with the text', (
    tester,
  ) async {
    final results = await _pump(
      tester,
      organizer: _FakeOrganizer((_) async => _result(items: const [])),
    );
    await tester.enterText(find.byKey(const Key('qa_paste_text')), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('qa_organize_ai')));
    await tester.pumpAndSettle();

    expect(results, isEmpty);
    expect(find.text(_l10n.t('organizeNoItemsFound')), findsOneWidget);
    expect(find.byKey(const Key('qa_paste_text')), findsOneWidget);
  });

  testWidgets('a server error is shown and the text is kept', (tester) async {
    await _pump(
      tester,
      organizer: _FakeOrganizer(
        (_) async => throw const CallableClientException(
          'OPENROUTER_API_KEY is not configured',
          code: 'failed-precondition',
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('qa_paste_text')), _reference);
    await tester.pump();
    await tester.tap(find.byKey(const Key('qa_organize_ai')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qa_organize_error')), findsOneWidget);
    expect(find.byKey(const Key('qa_paste_text')), findsOneWidget);
  });

  testWidgets('first use asks for the AI disclosure, once', (tester) async {
    final store = _FakeDisclosureStore(accepted: false);
    final organizer = _FakeOrganizer((_) async => _result());
    await _pump(tester, organizer: organizer, store: store);
    await tester.enterText(find.byKey(const Key('qa_paste_text')), _reference);
    await tester.pump();
    await tester.tap(find.byKey(const Key('qa_organize_ai')));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.t('voiceAiDisclosureTitle')), findsOneWidget);
    await tester.tap(find.text(_l10n.t('voiceAiDisclosureContinue')));
    await tester.pumpAndSettle();
    expect(store.accepted, isTrue);
    expect(organizer.calls, hasLength(1));
  });
}
