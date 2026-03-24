import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});

/// True when the device has no network connection.
final isOfflineProvider = Provider<bool>((ref) {
  // While the stream hasn't emitted yet, assume online.
  return ref.watch(connectivityProvider).value == false;
});
