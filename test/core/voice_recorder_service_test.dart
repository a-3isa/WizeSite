import 'package:buildtrack_app/core/services/voice_recorder_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('voice recording paths use the mobile-safe m4a container', () {
    expect(VoiceRecorderService.recordingFileExtension, '.m4a');
    expect(
      VoiceRecorderService.buildRecordingPath('/tmp/app', 123),
      '/tmp/app/voice_123.m4a',
    );
  });
}
