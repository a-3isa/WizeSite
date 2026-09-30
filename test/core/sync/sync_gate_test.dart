import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/sync/sync_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(SyncGatePhase phase, {Locale locale = const Locale('en')}) {
  return ProviderScope(
    overrides: [
      syncGatePhaseProvider.overrideWith((ref) => Stream.value(phase)),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: SyncGate(child: Text('workspace'))),
    ),
  );
}

void main() {
  group('syncGatePhaseFor', () {
    test('ready once any complete sync is stored, even offline', () {
      expect(
        syncGatePhaseFor(hasSynced: true, connected: false, connecting: false),
        SyncGatePhase.ready,
      );
    });
    test('loading while connecting or connected before first sync', () {
      expect(
        syncGatePhaseFor(hasSynced: null, connected: false, connecting: true),
        SyncGatePhase.loading,
      );
      expect(
        syncGatePhaseFor(hasSynced: false, connected: true, connecting: false),
        SyncGatePhase.loading,
      );
    });
    test('offline when never synced and not connected', () {
      expect(
        syncGatePhaseFor(hasSynced: null, connected: false, connecting: false),
        SyncGatePhase.offline,
      );
    });
  });

  testWidgets('ready shows the app', (tester) async {
    await tester.pumpWidget(_app(SyncGatePhase.ready));
    await tester.pump();
    expect(find.text('workspace'), findsOneWidget);
  });

  testWidgets('offline before first sync hides the empty workspace', (
    tester,
  ) async {
    await tester.pumpWidget(_app(SyncGatePhase.offline));
    await tester.pump();
    expect(find.text('workspace'), findsNothing);
    expect(find.textContaining('Connect to the internet'), findsOneWidget);
  });

  testWidgets('loading state is localized in Arabic', (tester) async {
    await tester.pumpWidget(
      _app(SyncGatePhase.loading, locale: const Locale('ar')),
    );
    await tester.pump();
    expect(find.text('workspace'), findsNothing);
    expect(find.text('جارٍ تحميل بياناتك…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
