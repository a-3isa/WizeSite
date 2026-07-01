import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppTelemetry {
  const AppTelemetry(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  Future<void> log(String event, [Map<String, Object?> details = const {}]) {
    final suffix = details.isEmpty ? '' : ' ${_format(details)}';
    return _crashlytics.log('$event$suffix');
  }

  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    bool fatal = false,
  }) {
    return _crashlytics.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: fatal,
    );
  }

  Future<T> trace<T>(
    String event,
    Future<T> Function() operation, {
    Map<String, Object?> details = const {},
  }) async {
    final stopwatch = Stopwatch()..start();
    await log('$event.start', details);
    try {
      final result = await operation();
      stopwatch.stop();
      await log('$event.success', {
        ...details,
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      return result;
    } catch (error, stackTrace) {
      stopwatch.stop();
      await log('$event.failure', {
        ...details,
        'duration_ms': stopwatch.elapsedMilliseconds,
        'error_type': error.runtimeType.toString(),
      });
      await recordError(error, stackTrace, reason: event);
      rethrow;
    }
  }

  String _format(Map<String, Object?> details) {
    final parts = <String>[];
    for (final entry in details.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      parts.add('${entry.key}=${_safeValue(entry.key, value)}');
    }
    return parts.join(' ');
  }

  Object _safeValue(String key, Object value) {
    if (key == 'error' || key.endsWith('_error')) {
      return value.runtimeType.toString();
    }
    return value;
  }
}

final appTelemetryProvider = Provider<AppTelemetry>((ref) {
  return AppTelemetry(FirebaseCrashlytics.instance);
});
