import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/services/microphone_permission_service.dart';
import 'package:buildtrack_app/core/services/voice_recorder_service.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/voice_expense/presentation/screens/voice_record_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('asks for microphone permission context before recording', (
    tester,
  ) async {
    final recorder = _FakeVoiceRecorderService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider.overrideWith(
            (ref) => Stream<List<Project>>.value(const []),
          ),
          voiceRecorderServiceProvider.overrideWithValue(recorder),
          microphonePermissionServiceProvider.overrideWithValue(
            _FakeMicrophonePermissionService(),
          ),
          currentUserSettingsProvider.overrideWith(
            (ref) => Stream<UserSettings>.value(
              UserSettings.defaults(userId: '', email: ''),
            ),
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
          home: VoiceRecordScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Allow microphone access'), findsOneWidget);
    expect(
      find.text(
        'Buildozer needs microphone access to record your voice expense note and turn it into a project expense.',
      ),
      findsOneWidget,
    );
    expect(recorder.startCalls, 0);
  });
}

class _FakeMicrophonePermissionService extends MicrophonePermissionService {
  @override
  Future<MicrophonePermissionStatus> status() async {
    return MicrophonePermissionStatus.denied;
  }

  @override
  Future<MicrophonePermissionStatus> request() async {
    return MicrophonePermissionStatus.granted;
  }
}

class _FakeVoiceRecorderService extends VoiceRecorderService {
  int startCalls = 0;

  @override
  Future<String> start() async {
    startCalls += 1;
    return 'test.wav';
  }
}
