import 'package:flutter/foundation.dart';

/// Lifecycle of a voice-expense capture session.
enum VoiceCaptureStatus {
  /// No recording in progress and nothing captured yet.
  idle,

  /// Actively recording audio.
  recording,

  /// A recording is captured and ready to play or process.
  ready,

  /// The captured recording is currently playing back.
  playing,

  /// The captured recording has been handed off for processing.
  processing,

  /// The session failed; [VoiceCaptureState.errorKey] holds a sanitized key.
  failure,
}

/// Immutable snapshot of a voice capture session.
///
/// Holds the elapsed/remaining countdown against [maxDuration], the live
/// normalized [amplitude] for waveform feedback, the captured [recordingPath],
/// a sanitized [errorKey] (never raw exception text), and the resolved
/// [currencyCode] forwarded to downstream processing.
@immutable
class VoiceCaptureState {
  const VoiceCaptureState({
    required this.currencyCode,
    this.status = VoiceCaptureStatus.idle,
    this.elapsed = Duration.zero,
    this.maxDuration = defaultMaxDuration,
    this.amplitude = 0.0,
    this.recordingPath,
    this.errorKey,
  });

  /// Default capture currency when the user has no configured currency.
  static const String fallbackCurrency = 'EGP';

  /// Hard recording limit.
  static const Duration defaultMaxDuration = Duration(seconds: 60);

  /// Builds the initial idle state, falling back to [fallbackCurrency] when the
  /// caller has no user currency available.
  factory VoiceCaptureState.initial({
    String? currencyCode,
    Duration maxDuration = defaultMaxDuration,
  }) {
    final trimmed = currencyCode?.trim();
    return VoiceCaptureState(
      currencyCode: (trimmed == null || trimmed.isEmpty)
          ? fallbackCurrency
          : trimmed,
      maxDuration: maxDuration,
    );
  }

  final VoiceCaptureStatus status;
  final Duration elapsed;
  final Duration maxDuration;

  /// Normalized microphone level in the range 0.0–1.0.
  final double amplitude;

  final String? recordingPath;

  /// Sanitized localization key for a failure (see `app_error_messages.dart`).
  final String? errorKey;

  final String currencyCode;

  /// Time left before the [maxDuration] auto-stop, never negative.
  Duration get remaining {
    final left = maxDuration - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  bool get isIdle => status == VoiceCaptureStatus.idle;
  bool get isRecording => status == VoiceCaptureStatus.recording;
  bool get isPlaying => status == VoiceCaptureStatus.playing;
  bool get isProcessing => status == VoiceCaptureStatus.processing;
  bool get hasError => status == VoiceCaptureStatus.failure;

  /// True once a recording exists and can be played or processed.
  bool get hasRecording =>
      recordingPath != null &&
      (status == VoiceCaptureStatus.ready ||
          status == VoiceCaptureStatus.playing ||
          status == VoiceCaptureStatus.processing);

  VoiceCaptureState copyWith({
    VoiceCaptureStatus? status,
    Duration? elapsed,
    Duration? maxDuration,
    double? amplitude,
    String? recordingPath,
    String? errorKey,
    String? currencyCode,
    bool clearError = false,
    bool clearRecordingPath = false,
  }) {
    return VoiceCaptureState(
      status: status ?? this.status,
      elapsed: elapsed ?? this.elapsed,
      maxDuration: maxDuration ?? this.maxDuration,
      amplitude: amplitude ?? this.amplitude,
      recordingPath: clearRecordingPath
          ? null
          : (recordingPath ?? this.recordingPath),
      errorKey: clearError ? null : (errorKey ?? this.errorKey),
      currencyCode: currencyCode ?? this.currencyCode,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VoiceCaptureState &&
        other.status == status &&
        other.elapsed == elapsed &&
        other.maxDuration == maxDuration &&
        other.amplitude == amplitude &&
        other.recordingPath == recordingPath &&
        other.errorKey == errorKey &&
        other.currencyCode == currencyCode;
  }

  @override
  int get hashCode => Object.hash(
    status,
    elapsed,
    maxDuration,
    amplitude,
    recordingPath,
    errorKey,
    currencyCode,
  );

  @override
  String toString() =>
      'VoiceCaptureState(status: $status, elapsed: $elapsed, '
      'amplitude: $amplitude, recordingPath: $recordingPath, '
      'errorKey: $errorKey, currencyCode: $currencyCode)';
}
