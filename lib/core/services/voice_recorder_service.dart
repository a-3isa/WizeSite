import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecorderService {
  VoiceRecorderService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  static const recordingFileExtension = '.wav';

  final AudioRecorder _recorder;

  Future<bool> hasPermission() {
    return _recorder.hasPermission();
  }

  Future<String> start() async {
    final hasMicPermission = await hasPermission();
    if (!hasMicPermission) {
      throw const VoiceRecorderException('Microphone permission is required.');
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = buildRecordingPath(tempDir.path, timestamp);

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 128000,
      ),
      path: path,
    );

    return path;
  }

  static String buildRecordingPath(String directoryPath, int timestamp) {
    final trimmed = directoryPath.replaceAll(RegExp(r'[\\/]$'), '');
    final separator = trimmed.contains('/') ? '/' : Platform.pathSeparator;
    return '$trimmed${separator}voice_$timestamp$recordingFileExtension';
  }

  Future<String?> stop() {
    return _recorder.stop();
  }

  Future<void> cancel() async {
    await _recorder.cancel();
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}

class VoiceRecorderException implements Exception {
  const VoiceRecorderException(this.message);

  final String message;

  @override
  String toString() => message;
}

final voiceRecorderServiceProvider = Provider<VoiceRecorderService>((ref) {
  final service = VoiceRecorderService();
  ref.onDispose(service.dispose);
  return service;
});
