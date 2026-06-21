import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/sync_error_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts normalized code from callable errors', () {
    final details = SyncErrorClassifier.detailsFrom(
      const CallableClientException(
        'Project is archived and can no longer accept payments.',
        code: 'permission_denied',
      ),
    );

    expect(details.code, 'permission-denied');
    expect(
      SyncErrorClassifier.categoryFrom(
        code: details.code,
        message: details.message,
      ),
      SyncFailureCategory.invalidTarget,
    );
  });

  test('treats not-found and invalid-argument as terminal invalid targets', () {
    expect(SyncErrorClassifier.isTerminalCode('not-found'), isTrue);
    expect(
      SyncErrorClassifier.categoryFrom(
        code: 'invalid-argument',
        message: 'Worker does not exist',
      ),
      SyncFailureCategory.invalidTarget,
    );
  });
}
