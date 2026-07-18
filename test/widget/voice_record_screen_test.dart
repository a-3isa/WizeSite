import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/services/microphone_permission_service.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/voice_expense/presentation/controllers/voice_capture_controller.dart';
import 'package:buildtrack_app/features/voice_expense/presentation/screens/voice_record_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeRecorder implements VoiceRecorderHandle {
  Object? startError;
  String startPath = '/tmp/rec.m4a';
  String? stopPath = '/tmp/rec.m4a';
  final StreamController<double> amp = StreamController<double>.broadcast();

  @override
  Future<String> start() async {
    if (startError != null) throw startError!;
    return startPath;
  }

  @override
  Future<String?> stop() async => stopPath;

  @override
  Future<void> cancel() async {}

  @override
  Stream<double> amplitudeStream() => amp.stream;
}

class _FakePlayer implements VoicePlaybackHandle {
  String? playedPath;
  final StreamController<void> complete = StreamController<void>.broadcast();

  @override
  Future<void> play(String path) async => playedPath = path;
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Stream<void> get onComplete => complete.stream;
  @override
  Future<void> dispose() async {}
}

class _GrantedPermissionService extends MicrophonePermissionService {
  @override
  Future<MicrophonePermissionStatus> status() async =>
      MicrophonePermissionStatus.granted;
}

Future<VoiceCaptureController> _pumpScreen(
  WidgetTester tester, {
  required _FakeRecorder recorder,
  required _FakePlayer player,
  String currency = 'USD',
}) async {
  final controller = VoiceCaptureController(
    recorder: recorder,
    player: player,
    currencyCode: currency,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        projectsProvider.overrideWith(
          (ref) => Stream<List<Project>>.value(const []),
        ),
        microphonePermissionServiceProvider.overrideWithValue(
          _GrantedPermissionService(),
        ),
        voiceCaptureControllerProvider.overrideWith((ref) => controller),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: VoiceRecordScreen(),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  testWidgets(
    'back navigation falls back to dashboard when voice is opened directly',
    (tester) async {
      final controller = VoiceCaptureController(
        recorder: _FakeRecorder(),
        player: _FakePlayer(),
        currencyCode: 'USD',
      );
      final router = GoRouter(
        initialLocation: AppRoutes.voiceExpense,
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (_, _) => const Scaffold(body: Text('Dashboard fallback')),
          ),
          GoRoute(
            path: AppRoutes.voiceExpense,
            builder: (_, _) => const VoiceRecordScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectsProvider.overrideWith(
              (ref) => Stream<List<Project>>.value(const []),
            ),
            microphonePermissionServiceProvider.overrideWithValue(
              _GrantedPermissionService(),
            ),
            voiceCaptureControllerProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp.router(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard fallback'), findsOneWidget);
    },
  );

  testWidgets(
    'idle state shows the mic and start prompt, no playback control',
    (tester) async {
      await _pumpScreen(
        tester,
        recorder: _FakeRecorder(),
        player: _FakePlayer(),
      );

      expect(find.byIcon(Icons.mic_outlined), findsOneWidget);
      expect(find.text('Tap the microphone to start'), findsOneWidget);
      expect(find.text('Play recording'), findsNothing);
    },
  );

  testWidgets('recording shows a live countdown and stop control', (
    tester,
  ) async {
    final controller = await _pumpScreen(
      tester,
      recorder: _FakeRecorder(),
      player: _FakePlayer(),
    );

    await controller.startRecording();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    expect(find.text('55s remaining'), findsOneWidget);

    await controller.cancel();
    await tester.pump();
  });

  testWidgets('exposes production playback when a recording is ready', (
    tester,
  ) async {
    final player = _FakePlayer();
    final controller = await _pumpScreen(
      tester,
      recorder: _FakeRecorder()..stopPath = '/tmp/ready.m4a',
      player: player,
    );

    await controller.startRecording();
    await controller.stopRecording();
    await tester.pump();

    final play = find.text('Play recording');
    expect(play, findsOneWidget);

    await tester.tap(play);
    await tester.pump();
    expect(player.playedPath, '/tmp/ready.m4a');

    await controller.cancel();
    await tester.pump();
  });

  testWidgets('cancel/rerecord returns to the idle prompt', (tester) async {
    final controller = await _pumpScreen(
      tester,
      recorder: _FakeRecorder(),
      player: _FakePlayer(),
    );

    await controller.startRecording();
    await controller.stopRecording();
    await tester.pump();
    expect(find.text('Tap the microphone to start'), findsNothing);

    await tester.tap(find.text('Cancel / Re-record'));
    await tester.pump();

    expect(find.text('Tap the microphone to start'), findsOneWidget);
  });

  testWidgets('shows a sanitized localized error when recording fails', (
    tester,
  ) async {
    final controller = await _pumpScreen(
      tester,
      recorder: _FakeRecorder()
        ..startError = Exception('microphone busy while recording audio'),
      player: _FakePlayer(),
    );

    await controller.startRecording();
    await tester.pump();

    expect(
      find.text('Recording failed. Check microphone access and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('forwards the selected user currency to the capture session', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      recorder: _FakeRecorder(),
      player: _FakePlayer(),
      currency: 'USD',
    );

    final element = tester.element(find.byType(VoiceRecordScreen));
    final state = ProviderScope.containerOf(
      element,
    ).read(voiceCaptureControllerProvider);
    expect(state.currencyCode, 'USD');
  });

  testWidgets('tapping the mic with granted permission starts recording', (
    tester,
  ) async {
    final recorder = _FakeRecorder();
    await _pumpScreen(tester, recorder: recorder, player: _FakePlayer());

    await tester.tap(find.byIcon(Icons.mic_outlined));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
  });
}
