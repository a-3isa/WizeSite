import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:cloud_functions/cloud_functions.dart';

String firebaseFunctionsErrorMessage(
  FirebaseFunctionsException error,
  AppLocalizations l10n,
) {
  final code = error.code.toLowerCase();
  switch (code) {
    case 'unauthenticated':
      return l10n.t('pleaseLoginFirst');
    case 'permission-denied':
      return l10n.t('actionNotAllowed');
    case 'not-found':
    case 'unimplemented':
      return l10n.t('featureTemporarilyUnavailable');
    case 'unavailable':
    case 'deadline-exceeded':
    case 'resource-exhausted':
      return l10n.t('serviceUnavailable');
  }

  final message = error.message?.trim();
  if (_isHumanReadableMessage(message: message, code: code)) {
    return message!;
  }

  return l10n.t('unexpectedErrorTryAgain');
}

bool _isHumanReadableMessage({required String? message, required String code}) {
  if (message == null || message.isEmpty) {
    return false;
  }

  final normalizedMessage = message.toLowerCase().replaceAll('-', '_').trim();
  final normalizedCode = code.replaceAll('-', '_').trim();
  if (normalizedMessage == normalizedCode) {
    return false;
  }

  const machineValues = <String>{
    'not_found',
    'permission_denied',
    'unauthenticated',
    'internal',
    'unavailable',
    'deadline_exceeded',
    'resource_exhausted',
    'invalid_argument',
    'failed_precondition',
    'unimplemented',
    'already_exists',
  };
  if (machineValues.contains(normalizedMessage)) {
    return false;
  }

  if (RegExp(r'^[A-Z0-9_]+$').hasMatch(message)) {
    return false;
  }

  return true;
}
