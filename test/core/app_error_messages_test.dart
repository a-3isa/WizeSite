import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appErrorMessageKey', () {
    test('maps Firestore failures by gRPC status code', () {
      expect(
        appErrorMessageKey(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        ),
        'errorPermissionDenied',
      );
      expect(
        appErrorMessageKey(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        'errorNetwork',
      );
      expect(
        appErrorMessageKey(
          FirebaseException(plugin: 'cloud_firestore', code: 'unauthenticated'),
        ),
        'errorUnauthenticated',
      );
      expect(
        appErrorMessageKey(
          FirebaseException(plugin: 'cloud_firestore', code: 'not-found'),
        ),
        'errorNotFound',
      );
      expect(
        appErrorMessageKey(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'resource-exhausted',
          ),
        ),
        'errorQuota',
      );
    });

    test('maps upload failures to a storage-specific or scoped key', () {
      expect(
        appErrorMessageKey(
          const StorageUploadException('x', code: 'upload-failed'),
        ),
        'errorStorage',
      );
      expect(
        appErrorMessageKey(
          const StorageUploadException('x', code: 'permission-denied'),
        ),
        'errorPermissionDenied',
      );
      expect(
        appErrorMessageKey(
          const StorageUploadException('x', code: 'unavailable'),
        ),
        'errorNetwork',
      );
    });

    test('maps Auth failures', () {
      expect(
        appErrorMessageKey(FirebaseAuthException(code: 'wrong-password')),
        'errorAuthInvalidCredentials',
      );
      expect(
        appErrorMessageKey(FirebaseAuthException(code: 'invalid-credential')),
        'errorAuthInvalidCredentials',
      );
      expect(
        appErrorMessageKey(
          FirebaseAuthException(code: 'network-request-failed'),
        ),
        'errorNetwork',
      );
      expect(
        appErrorMessageKey(FirebaseAuthException(code: 'too-many-requests')),
        'errorAuth',
      );
    });

    test('maps recording failures', () {
      expect(
        appErrorMessageKey(
          Exception('Microphone permission denied while recording audio'),
        ),
        'errorRecording',
      );
    });

    test('maps queued callable failures by code', () {
      expect(
        appErrorMessageKey(
          const CallableClientException('nope', code: 'unauthenticated'),
        ),
        'errorUnauthenticated',
      );
      expect(
        appErrorMessageKey(
          const CallableClientException('busy', code: 'unavailable'),
        ),
        'errorNetwork',
      );
      expect(
        appErrorMessageKey(
          const CallableClientException(
            'INVITE_UNAVAILABLE',
            code: 'not-found',
          ),
        ),
        'inviteUnavailable',
      );
    });

    test('falls back to a generic key for unknown failures', () {
      expect(
        appErrorMessageKey(Exception('totally weird internal detail')),
        'errorUnknown',
      );
      expect(appErrorMessageKey('a bare string'), 'errorUnknown');
    });
  });

  group('appErrorMessage', () {
    final en = AppLocalizations(const Locale('en'));

    test('returns a localized, non-empty message', () {
      final message = appErrorMessage(
        en,
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      expect(message.trim(), isNotEmpty);
      // Should not be the raw key passthrough.
      expect(message, isNot('errorPermissionDenied'));
    });

    test('never leaks raw exception text', () {
      final message = appErrorMessage(
        en,
        Exception('SECRET_STACK_DETAIL_12345'),
      );
      expect(message, isNot(contains('SECRET_STACK_DETAIL_12345')));
      expect(message, isNot(contains('Exception')));
    });

    test('every mapped key resolves to a real localized string', () {
      final keys = appErrorMessageKeys;
      for (final key in keys) {
        expect(
          AppLocalizations.requiredKeys,
          contains(key),
          reason: 'Missing localization for $key',
        );
        expect(en.t(key), isNot(key), reason: '$key is not translated');
      }
    });
  });
}
