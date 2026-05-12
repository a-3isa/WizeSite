import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

enum MicrophonePermissionStatus { granted, denied, blocked }

class MicrophonePermissionService {
  Future<MicrophonePermissionStatus> status() async {
    return _mapStatus(await Permission.microphone.status);
  }

  Future<MicrophonePermissionStatus> request() async {
    return _mapStatus(await Permission.microphone.request());
  }

  Future<bool> openSettings() {
    return openAppSettings();
  }

  MicrophonePermissionStatus _mapStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return MicrophonePermissionStatus.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return MicrophonePermissionStatus.blocked;
    }
    return MicrophonePermissionStatus.denied;
  }
}

final microphonePermissionServiceProvider =
    Provider<MicrophonePermissionService>((ref) {
      return MicrophonePermissionService();
    });
