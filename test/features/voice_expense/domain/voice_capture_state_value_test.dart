import 'package:buildtrack_app/features/voice_expense/domain/voice_capture_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceCaptureState value semantics', () {
    test('initial factory falls back to default currency and clamps remaining',
        () {
      final s = VoiceCaptureState.initial();
      expect(s.currencyCode, VoiceCaptureState.fallbackCurrency);
      expect(s.status, VoiceCaptureStatus.idle);
      expect(s.isIdle, isTrue);
      expect(s.remaining, VoiceCaptureState.defaultMaxDuration);
    });

    test('remaining never goes negative past the max duration', () {
      const s = VoiceCaptureState(
        currencyCode: 'USD',
        maxDuration: Duration(seconds: 60),
        elapsed: Duration(seconds: 75),
      );
      expect(s.remaining, Duration.zero);
    });

    test('status getters reflect the current status', () {
      VoiceCaptureState withStatus(VoiceCaptureStatus s) =>
          VoiceCaptureState(currencyCode: 'USD', status: s, recordingPath: '/p');
      expect(withStatus(VoiceCaptureStatus.recording).isRecording, isTrue);
      expect(withStatus(VoiceCaptureStatus.playing).isPlaying, isTrue);
      expect(withStatus(VoiceCaptureStatus.processing).isProcessing, isTrue);
      expect(withStatus(VoiceCaptureStatus.failure).hasError, isTrue);
      expect(withStatus(VoiceCaptureStatus.ready).hasRecording, isTrue);
      expect(withStatus(VoiceCaptureStatus.idle).hasRecording, isFalse);
    });

    test('copyWith updates provided fields and supports explicit clears', () {
      const base = VoiceCaptureState(
        currencyCode: 'USD',
        status: VoiceCaptureStatus.failure,
        recordingPath: '/old',
        errorKey: 'errorRecording',
        amplitude: 0.4,
      );

      final updated = base.copyWith(
        status: VoiceCaptureStatus.recording,
        amplitude: 0.9,
      );
      expect(updated.status, VoiceCaptureStatus.recording);
      expect(updated.amplitude, 0.9);
      expect(updated.recordingPath, '/old');
      expect(updated.errorKey, 'errorRecording');

      final cleared =
          base.copyWith(clearError: true, clearRecordingPath: true);
      expect(cleared.errorKey, isNull);
      expect(cleared.recordingPath, isNull);
      expect(cleared.currencyCode, 'USD');
    });

    test('equality and hashCode are value-based', () {
      const a = VoiceCaptureState(currencyCode: 'USD', amplitude: 0.5);
      const b = VoiceCaptureState(currencyCode: 'USD', amplitude: 0.5);
      const c = VoiceCaptureState(currencyCode: 'USD', amplitude: 0.6);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('USD'));
    });
  });
}
