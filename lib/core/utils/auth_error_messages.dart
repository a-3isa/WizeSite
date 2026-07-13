import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Maps Firebase Auth failures to localized, human-readable messages.
///
/// Shared by sign-in, sign-up and password-reset so the same Firebase code
/// never produces different wording depending on which screen you are on.
class AuthErrorMessages {
  const AuthErrorMessages._();

  /// Normalizes a Firebase code, which may arrive prefixed on some platforms.
  static String _normalize(String code) =>
      code.replaceFirst('firebase_auth/', '');

  /// Message for a failed sign-in attempt.
  static String signIn(AppLocalizations l10n, Object error) {
    if (error is FirebaseAuthException) {
      switch (_normalize(error.code)) {
        case 'user-not-found':
          return l10n.t('authNoAccountFound');
        case 'wrong-password':
        case 'invalid-credential':
          return l10n.t('authIncorrectPassword');
        case 'invalid-email':
          return l10n.t('authInvalidEmail');
        case 'user-disabled':
          return l10n.t('authAccountDisabled');
        case 'too-many-requests':
          return l10n.t('authTooManyAttempts');
        case 'network-request-failed':
          return l10n.t('authNetworkError');
        case 'operation-not-allowed':
          return l10n.t('authOperationNotAllowed');
        case 'account-exists-with-different-credential':
          return l10n.t('authDifferentProvider');
      }
    }
    if (error is TimeoutException) {
      return l10n.t('authNetworkError');
    }
    return l10n.t('authSignInFailed');
  }

  /// Message for a failed account creation attempt.
  static String signUp(AppLocalizations l10n, Object error) {
    if (error is FirebaseAuthException) {
      switch (_normalize(error.code)) {
        case 'email-already-in-use':
          return l10n.t('authEmailAlreadyInUse');
        case 'invalid-email':
          return l10n.t('authInvalidEmailFormat');
        case 'weak-password':
          return l10n.t('authWeakPassword');
        case 'operation-not-allowed':
          return l10n.t('authOperationNotAllowed');
        case 'too-many-requests':
          return l10n.t('authTooManyAttempts');
        case 'network-request-failed':
          return l10n.t('authNetworkError');
      }
    }
    if (error is TimeoutException) {
      return l10n.t('authNetworkError');
    }
    return l10n.t('authSignUpFailed');
  }

  /// Message for a failed password-reset request.
  ///
  /// `user-not-found` is deliberately NOT surfaced as "no such account" — that
  /// would let anyone probe which emails are registered. The caller shows the
  /// same success confirmation either way.
  static String passwordReset(AppLocalizations l10n, Object error) {
    if (error is FirebaseAuthException) {
      switch (_normalize(error.code)) {
        case 'invalid-email':
          return l10n.t('authInvalidEmail');
        case 'too-many-requests':
          return l10n.t('authTooManyAttempts');
        case 'network-request-failed':
          return l10n.t('authNetworkError');
        case 'operation-not-allowed':
          return l10n.t('authOperationNotAllowed');
      }
    }
    if (error is TimeoutException) {
      return l10n.t('authNetworkError');
    }
    return l10n.t('authSignInFailed');
  }
}
