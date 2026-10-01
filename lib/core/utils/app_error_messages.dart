import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:buildtrack_app/core/services/sync_error_classifier.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The complete set of localization keys this mapper can return. Used by tests
/// to guarantee every reachable key resolves to a real localized string.
const List<String> appErrorMessageKeys = <String>[
  'errorNetwork',
  'errorPermissionDenied',
  'errorUnauthenticated',
  'errorNotFound',
  'errorQuota',
  'errorStorage',
  'errorAuth',
  'errorAuthInvalidCredentials',
  'errorRecording',
  'errorUnknown',
  'inviteUnavailable',
];

/// Maps an arbitrary thrown [error] to a stable, localized message key.
///
/// This is the single sanitization boundary between low-level failures
/// (server RPCs, uploads, auth, recording, queued calls) and the UI. Callers
/// must never render `error.toString()`; pass the error here instead so the
/// app shows a friendly, translated message and never leaks raw exception or
/// stack text.
String appErrorMessageKey(Object? error) {
  if (error == null) return 'errorUnknown';

  // Authentication failures (FirebaseAuthException extends FirebaseException).
  if (error is FirebaseAuthException) {
    return _authKey(error.code);
  }

  if (error is FirebaseException) {
    if (error.plugin == 'firebase_auth') return _authKey(error.code);
    return _statusCodeKey(error.code, error.message ?? '');
  }

  // File uploads: server error codes, anything else is a storage failure.
  if (error is StorageUploadException) {
    final key = _statusCodeKey(error.code, error.message);
    return key == 'errorUnknown' ? 'errorStorage' : key;
  }

  if (error is CallableClientException) {
    return _statusCodeKey(error.code, error.message);
  }

  // Recording failures surface as plain exceptions from the `record` package.
  final raw = error.toString().toLowerCase();
  if (_looksLikeRecordingFailure(raw)) {
    return 'errorRecording';
  }

  // Last resort: try to recover an embedded gRPC code from the text.
  final details = SyncErrorClassifier.detailsFrom(error);
  if (details.code != null) {
    return _statusCodeKey(details.code, details.message);
  }

  return 'errorUnknown';
}

/// Resolves [error] to a localized, sanitized message string.
String appErrorMessage(AppLocalizations l10n, Object? error) {
  return l10n.t(appErrorMessageKey(error));
}

bool _looksLikeRecordingFailure(String normalized) {
  return normalized.contains('microphone') ||
      normalized.contains('mic ') ||
      (normalized.contains('record') && normalized.contains('audio')) ||
      normalized.contains('recording');
}

String _authKey(String? code) {
  switch (_normalize(code)) {
    case 'invalid-credential':
    case 'invalid-login-credentials':
    case 'wrong-password':
    case 'user-not-found':
    case 'invalid-email':
      return 'errorAuthInvalidCredentials';
    case 'network-request-failed':
      return 'errorNetwork';
    default:
      return 'errorAuth';
  }
}

String _statusCodeKey(String? code, String message) {
  switch (_normalize(code)) {
    case 'unavailable':
    case 'deadline-exceeded':
    case 'network-request-failed':
      return 'errorNetwork';
    case 'permission-denied':
      return 'errorPermissionDenied';
    case 'unauthenticated':
      return 'errorUnauthenticated';
    case 'not-found':
      if (message.toUpperCase().contains('INVITE_UNAVAILABLE')) {
        return 'inviteUnavailable';
      }
      return 'errorNotFound';
    case 'resource-exhausted':
    case 'limit-reached':
      return 'errorQuota';
    case 'failed-precondition':
      return SyncErrorClassifier.categoryFrom(
                code: 'failed-precondition',
                message: message,
              ) ==
              SyncFailureCategory.quota
          ? 'errorQuota'
          : 'errorUnknown';
    default:
      return 'errorUnknown';
  }
}

String? _normalize(String? code) {
  final trimmed = code?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.toLowerCase().replaceAll('_', '-');
}
