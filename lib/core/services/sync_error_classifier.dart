import 'package:buildtrack_app/core/services/callable_client.dart';

class SyncErrorDetails {
  const SyncErrorDetails({required this.message, this.code});

  final String message;
  final String? code;
}

enum SyncFailureCategory {
  quota,
  unauthenticated,
  invalidTarget,
  permission,
  generic,
}

class SyncErrorClassifier {
  const SyncErrorClassifier._();

  static SyncErrorDetails detailsFrom(Object error) {
    if (error is CallableClientException) {
      return SyncErrorDetails(
        message: error.message.trim(),
        code: _normalizeCode(error.code),
      );
    }

    final raw = error.toString().trim();
    return SyncErrorDetails(message: raw, code: _extractCodeFromText(raw));
  }

  static bool isTerminal(Object error) {
    final details = detailsFrom(error);
    return isTerminalCode(details.code) ||
        _messageImpliesTerminal(details.message);
  }

  static bool isTerminalCode(String? code) {
    switch (_normalizeCode(code)) {
      case 'failed-precondition':
      case 'limit_reached':
      case 'permission-denied':
      case 'invalid-argument':
      case 'not-found':
      case 'already-exists':
        return true;
      default:
        return false;
    }
  }

  static SyncFailureCategory categoryFrom({String? code, String? message}) {
    final normalizedCode = _normalizeCode(code);
    final normalizedMessage = (message ?? '').toLowerCase();

    if (normalizedCode == 'failed-precondition' ||
        normalizedCode == 'limit_reached') {
      if (normalizedMessage.contains('archived') ||
          normalizedMessage.contains('no longer accept') ||
          normalizedMessage.contains('no longer valid') ||
          // Contract-and-payment invariant rejections. Without these two the
          // messages fall through to `quota` below and the user is told they
          // hit a plan limit, which is simply untrue.
          normalizedMessage.contains('contract value') ||
          normalizedMessage.contains('before recording payments')) {
        return SyncFailureCategory.invalidTarget;
      }
      return SyncFailureCategory.quota;
    }
    if (normalizedCode == 'unauthenticated') {
      return SyncFailureCategory.unauthenticated;
    }
    if (normalizedCode == 'permission-denied') {
      if (normalizedMessage.contains('archived') ||
          normalizedMessage.contains('workspace') ||
          normalizedMessage.contains('project does not exist') ||
          normalizedMessage.contains('worker does not exist')) {
        return SyncFailureCategory.invalidTarget;
      }
      return SyncFailureCategory.permission;
    }
    if (normalizedCode == 'invalid-argument' || normalizedCode == 'not-found') {
      return SyncFailureCategory.invalidTarget;
    }
    return SyncFailureCategory.generic;
  }

  static String? _normalizeCode(String? code) {
    final trimmed = code?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed.toLowerCase().replaceAll('_', '-');
  }

  static String? _extractCodeFromText(String text) {
    final match = RegExp(
      r'\[([a-z0-9_-]+)\]',
      caseSensitive: false,
    ).firstMatch(text);
    return _normalizeCode(match?.group(1));
  }

  static bool _messageImpliesTerminal(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('failed-precondition') ||
        normalized.contains('limit_reached') ||
        normalized.contains('permission-denied') ||
        normalized.contains('permission_denied') ||
        normalized.contains('invalid-argument') ||
        normalized.contains('invalid_argument') ||
        normalized.contains('not-found') ||
        normalized.contains('not_found');
  }
}
