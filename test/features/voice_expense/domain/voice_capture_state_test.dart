import 'dart:async';

import 'package:buildtrack_app/features/voice_expense/domain/voice_capture_state.dart';
import 'package:buildtrack_app/features/voice_expense/presentation/controllers/voice_capture_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRecorder implements VoiceRecorderHandle {
  bool started = false;
  bool stopped = false;
  bool cancelled = false;
  Object? startError;
  Object? stopError;
  String startPath = '/tmp/rec.m4a';
  String? stopPath = '/tmp/rec.m4a';
  final StreamController<double> amp = StreamController<double>.broadcast();

  @override
  Future<String> start() async {
    if (startError != null) throw startError!;
    started = true;
    return startPath;
  }

  @override
  Future<String?> stop() async {
    if (stopError != null) throw stopError!;
    stopped = true;
    return stopPath;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Stream<double> amplitudeStream() => amp.stream;
}

class _FakePlayer implements VoicePlaybackHandle {
  bool playing = false;
  bool paused = false;
  bool stopped = false;
  bool disposed = false;
  String? playedPath;
  final StreamController<void> _complete = StreamController<void>.broadcast();

  @override
  Future<void> play(String path) async {
    playing = true;
    playedPath = path;
  }

  @override
  Future<void> pause() async {
    paused = true;
    playing = false;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    playing = false;
  }

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  void completePlayback() => _complete.add(null);
}

VoiceCaptureController _make({
  _FakeRecorder? recorder,
  _FakePlayer? player,
  String? currencyCode = 'USD',
  Duration maxDuration = const Duration(seconds: 60),
}) {
  return VoiceCaptureController(
    recorder: recorder ?? _FakeRecorder(),
    player: player ?? _FakePlayer(),
    currencyCode: currencyCode,
    maxDuration: maxDuration,
  );
}

void main() {
  group('initial state', () {
    test('starts idle and forwards the user currency', () {
      final c = _make(currencyCode: 'USD');
      expect(c.state.status, VoiceCaptureStatus.idle);
      expect(c.state.currencyCode, 'USD');
      expect(c.state.remaining, const Duration(seconds: 60));
      c.dispose();
    });

    test('falls back to the default currency when none is provided', () {
      expect(
        _make(currencyCode: null).state.currencyCode,
        VoiceCaptureState.fallbackCurrency,
      );
      expect(
        _make(currencyCode: '   ').state.currencyCode,
        VoiceCaptureState.fallbackCurrency,
      );
    });
  });

  group('recording lifecycle', () {
    test('startRecording moves to recording and captures the path', () async {
      final recorder = _FakeRecorder()..startPath = '/tmp/a.m4a';
      final c = _make(recorder: recorder);

      await c.startRecording();

      expect(c.state.status, VoiceCaptureStatus.recording);
      expect(c.state.recordingPath, '/tmp/a.m4a');
      expect(recorder.started, isTrue);
      c.dispose();
    });

    test('amplitude updates while recording', () async {
      final recorder = _FakeRecorder();
      final c = _make(recorder: recorder);
      await c.startRecording();

      recorder.amp.add(0.7);
      await Future<void>.delayed(Duration.zero);

      expect(c.state.amplitude, closeTo(0.7, 1e-9));
      c.dispose();
    });

    test('manual stopRecording moves to ready with the final path', () async {
      final recorder = _FakeRecorder()..stopPath = '/tmp/final.m4a';
      final c = _make(recorder: recorder);
      await c.startRecording();

      await c.stopRecording();

      expect(c.state.status, VoiceCaptureStatus.ready);
      expect(c.state.recordingPath, '/tmp/final.m4a');
      expect(recorder.stopped, isTrue);
      c.dispose();
    });

    test('auto-stops at the 60-second limit', () {
      fakeAsync((async) {
        final recorder = _FakeRecorder();
        final c = _make(recorder: recorder);

        c.startRecording();
        async.flushMicrotasks();
        expect(c.state.isRecording, isTrue);

        async.elapse(const Duration(seconds: 59));
        async.flushMicrotasks();
        expect(c.state.isRecording, isTrue, reason: 'not yet at the limit');

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(c.state.status, VoiceCaptureStatus.ready);
        expect(recorder.stopped, isTrue);
        c.dispose();
      });
    });

    test('counts down remaining time each second', () {
      fakeAsync((async) {
        final c = _make();
        c.startRecording();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(c.state.elapsed, const Duration(seconds: 10));
        expect(c.state.remaining, const Duration(seconds: 50));
        c.dispose();
      });
    });
  });

  group('playback lifecycle', () {
    test(
      'togglePlayback plays the ready recording then returns to ready',
      () async {
        final player = _FakePlayer();
        final recorder = _FakeRecorder()..stopPath = '/tmp/play.m4a';
        final c = _make(recorder: recorder, player: player);
        await c.startRecording();
        await c.stopRecording();

        await c.togglePlayback();
        expect(c.state.status, VoiceCaptureStatus.playing);
        expect(player.playedPath, '/tmp/play.m4a');

        player.completePlayback();
        await Future<void>.delayed(Duration.zero);
        expect(c.state.status, VoiceCaptureStatus.ready);
        c.dispose();
      },
    );

    test('togglePlayback pauses while playing', () async {
      final player = _FakePlayer();
      final c = _make(player: player);
      await c.startRecording();
      await c.stopRecording();
      await c.togglePlayback();

      await c.togglePlayback();

      expect(c.state.status, VoiceCaptureStatus.ready);
      expect(player.paused, isTrue);
      c.dispose();
    });
  });

  group('cancellation and processing', () {
    test('cancel resets to idle and cancels the recorder', () async {
      final recorder = _FakeRecorder();
      final c = _make(recorder: recorder, currencyCode: 'SAR');
      await c.startRecording();

      await c.cancel();

      expect(c.state.status, VoiceCaptureStatus.idle);
      expect(c.state.recordingPath, isNull);
      expect(c.state.elapsed, Duration.zero);
      expect(c.state.currencyCode, 'SAR', reason: 'currency is preserved');
      expect(recorder.cancelled, isTrue);
      c.dispose();
    });

    test(
      'markProcessing transitions a ready recording to processing',
      () async {
        final c = _make();
        await c.startRecording();
        await c.stopRecording();

        c.markProcessing();

        expect(c.state.status, VoiceCaptureStatus.processing);
        c.dispose();
      },
    );
  });

  group('failure handling', () {
    test('records a sanitized error key when starting fails', () async {
      final recorder = _FakeRecorder()
        ..startError = Exception(
          'Microphone permission denied while recording',
        );
      final c = _make(recorder: recorder);

      await c.startRecording();

      expect(c.state.status, VoiceCaptureStatus.failure);
      expect(c.state.errorKey, 'errorRecording');
      c.dispose();
    });

    test('starting again clears a previous error', () async {
      final recorder = _FakeRecorder()
        ..startError = Exception('mic fail audio');
      final c = _make(recorder: recorder);
      await c.startRecording();
      expect(c.state.hasError, isTrue);

      recorder.startError = null;
      await c.startRecording();

      expect(c.state.status, VoiceCaptureStatus.recording);
      expect(c.state.errorKey, isNull);
      c.dispose();
    });
  });
}
