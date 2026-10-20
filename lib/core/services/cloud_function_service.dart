import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/utils/local_date_key.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CloudFunctionService {
  const CloudFunctionService(this._client);

  final CallableClient _client;

  Future<Map<String, dynamic>> processVoiceExpense({
    required String storagePath,
    required List<Map<String, String>> projects,
    required String currency,
    required String languageHint,
  }) async {
    try {
      return await _client.call<Map<String, dynamic>>(
        functionName: 'processVoiceExpense',
        payload: {
          'storagePath': storagePath,
          'projects': projects,
          'currency': currency,
          'languageHint': languageHint,
          // Relative dates ("امبارح") resolve against the device's day.
          'today': localDateKey(DateTime.now()),
        },
        parseResult: (result) => Map<String, dynamic>.from(result as Map),
        defaultErrorMessage: 'Failed to process voice expense.',
        // Self-hosted (spec 004, T083): the server allows 120 s for
        // transcription + parsing, and the same recording reuses its result.
        idempotencyKey: 'voice:$storagePath',
        timeout: const Duration(seconds: 130),
      );
    } on CallableClientException catch (error) {
      throw CloudFunctionServiceException(error.message, code: error.code);
    }
  }
}

class CloudFunctionServiceException implements Exception {
  const CloudFunctionServiceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

final cloudFunctionServiceProvider = Provider<CloudFunctionService>((ref) {
  return CloudFunctionService(ref.watch(callableClientProvider));
});
