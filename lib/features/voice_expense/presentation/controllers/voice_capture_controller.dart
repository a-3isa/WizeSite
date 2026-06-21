import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:buildtrack_app/core/services/voice_recorder_service.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/voice_expense/domain/voice_capture_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Recording seam the controller depends on, so tests can drive the state
/// machine without touching platform channels.
abstract class VoiceRecorderHandle {
  Future<String> start();
  Future<String?> stop();
  Future<void> cancel();
  Stream<double> amplitudeStream();
}

/// Playback seam the controller depends on.
abstract class VoicePlaybackHandle {
  Future<void> play(String path);
  Future<void> pause();
  Future<void> stop();
  Stream<void> get onComplete;
  Future<void> dispose();
}

/// Drives the voice-expense capture state machine: recording with a hard
/// 60-second auto-stop, live amplitude feedback, playback of the captured clip,
/// cancellation, and sanitized failures. UI never reads platform APIs directly.
class VoiceCaptureController extends StateNotifier<VoiceCaptureState> {
  VoiceCaptureController({
    required VoiceRecorderHandle recorder,
    required VoicePlaybackHandle player,
    String? currencyCode,
    Duration maxDuration = VoiceCaptureState.defaultMaxDuration,
  }) : _recorder = recorder,
       _player = player,
       super(
         VoiceCaptureState.initial(
           currencyCode: currencyCode,
           maxDuration: maxDuration,
         ),
       ) {
    _completeSub = _player.onComplete.listen((_) => _onPlaybackComplete());
  }

  final VoiceRecorderHandle _recorder;
  final VoicePlaybackHandle _player;

  Timer? _timer;
  StreamSubscription<double>? _amplitudeSub;
  StreamSubscription<void>? _completeSub;

  Future<void> startRecording() async {
    if (state.status == VoiceCaptureStatus.recording) return;
    try {
      final path = await _recorder.start();
      state = state.copyWith(
        status: VoiceCaptureStatus.recording,
        elapsed: Duration.zero,
        amplitude: 0,
        recordingPath: path,
        clearError: true,
      );
      _amplitudeSub = _recorder.amplitudeStream().listen(_onAmplitude);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } catch (error) {
      _enterFailure(error);
    }
  }

  void _onAmplitude(double level) {
    if (state.status != VoiceCaptureStatus.recording) return;
    state = state.copyWith(amplitude: level.clamp(0.0, 1.0));
  }

  void _tick() {
    final next = state.elapsed + const Duration(seconds: 1);
    state = state.copyWith(elapsed: next);
    if (next >= state.maxDuration) {
      unawaited(stopRecording());
    }
  }

  Future<void> stopRecording() async {
    if (state.status != VoiceCaptureStatus.recording) return;
    _stopTimers();
    try {
      final path = await _recorder.stop();
      state = state.copyWith(
        status: VoiceCaptureStatus.ready,
        amplitude: 0,
        recordingPath: path ?? state.recordingPath,
      );
    } catch (error) {
      _enterFailure(error);
    }
  }

  Future<void> togglePlayback() async {
    final path = state.recordingPath;
    if (path == null) return;
    if (state.status == VoiceCaptureStatus.playing) {
      await _player.pause();
      state = state.copyWith(status: VoiceCaptureStatus.ready);
      return;
    }
    if (state.status != VoiceCaptureStatus.ready) return;
    try {
      await _player.play(path);
      state = state.copyWith(status: VoiceCaptureStatus.playing);
    } catch (error) {
      _enterFailure(error);
    }
  }

  void _onPlaybackComplete() {
    if (state.status == VoiceCaptureStatus.playing) {
      state = state.copyWith(status: VoiceCaptureStatus.ready);
    }
  }

  Future<void> cancel() async {
    _stopTimers();
    if (state.status == VoiceCaptureStatus.recording) {
      await _recorder.cancel();
    }
    if (state.status == VoiceCaptureStatus.playing) {
      await _player.stop();
    }
    state = VoiceCaptureState.initial(
      currencyCode: state.currencyCode,
      maxDuration: state.maxDuration,
    );
  }

  /// Marks the captured recording as handed off for processing.
  void markProcessing() {
    if (state.recordingPath != null) {
      state = state.copyWith(status: VoiceCaptureStatus.processing);
    }
  }

  void _enterFailure(Object error) {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(
      status: VoiceCaptureStatus.failure,
      amplitude: 0,
      errorKey: appErrorMessageKey(error),
    );
  }

  void _stopTimers() {
    _timer?.cancel();
    _timer = null;
    final sub = _amplitudeSub;
    _amplitudeSub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitudeSub?.cancel();
    _completeSub?.cancel();
    super.dispose();
  }
}

/// Adapts the core [VoiceRecorderService] to [VoiceRecorderHandle].
class VoiceRecorderServiceHandle implements VoiceRecorderHandle {
  VoiceRecorderServiceHandle(this._service);

  final VoiceRecorderService _service;

  @override
  Future<String> start() => _service.start();

  @override
  Future<String?> stop() => _service.stop();

  @override
  Future<void> cancel() => _service.cancel();

  @override
  Stream<double> amplitudeStream() => _service.amplitudeStream();
}

/// Adapts an audioplayers [AudioPlayer] to [VoicePlaybackHandle].
class AudioPlayerPlaybackHandle implements VoicePlaybackHandle {
  AudioPlayerPlaybackHandle([AudioPlayer? player])
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> play(String path) => _player.play(DeviceFileSource(path));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> dispose() => _player.dispose();
}

/// Provides a [VoiceCaptureController] wired to real services, with the user's
/// configured currency forwarded (falling back to the default).
final voiceCaptureControllerProvider =
    StateNotifierProvider.autoDispose<
      VoiceCaptureController,
      VoiceCaptureState
    >((ref) {
      final currency = ref
          .watch(currentUserSettingsProvider)
          .valueOrNull
          ?.defaultCurrency;
      final player = AudioPlayerPlaybackHandle();
      final controller = VoiceCaptureController(
        recorder: VoiceRecorderServiceHandle(
          ref.watch(voiceRecorderServiceProvider),
        ),
        player: player,
        currencyCode: currency,
      );
      ref.onDispose(player.dispose);
      return controller;
    });
