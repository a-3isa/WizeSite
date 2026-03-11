import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CloudFunctionService {
  const CloudFunctionService(this._functions);

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> processVoiceExpense({
    required String storagePath,
    required List<Map<String, String>> projects,
    required String currency,
    required String languageHint,
  }) async {
    final callable = _functions.httpsCallable('processVoiceExpense');
    final response = await callable.call<Map<String, dynamic>>({
      'storagePath': storagePath,
      'projects': projects,
      'currency': currency,
      'languageHint': languageHint,
    });

    return response.data;
  }
}

class CloudFunctionServiceException implements Exception {
  const CloudFunctionServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

final cloudFunctionServiceProvider = Provider<CloudFunctionService>((ref) {
  return CloudFunctionService(FirebaseFunctions.instance);
});
