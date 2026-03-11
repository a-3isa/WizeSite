import 'package:buildtrack_app/core/services/cloud_function_service.dart';
import 'package:buildtrack_app/core/services/expense_save_service.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:buildtrack_app/features/voice_expense/domain/voice_expense_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VoiceExpenseRepository {
  const VoiceExpenseRepository({
    required StorageUploadService uploadService,
    required CloudFunctionService cloudFunctionService,
    required ExpenseSaveService expenseSaveService,
  }) : _uploadService = uploadService,
       _cloudFunctionService = cloudFunctionService,
       _expenseSaveService = expenseSaveService;

  final StorageUploadService _uploadService;
  final CloudFunctionService _cloudFunctionService;
  final ExpenseSaveService _expenseSaveService;

  Future<VoiceExpenseParseResponse> processVoiceRecording({
    required String userId,
    required String localAudioPath,
    required List<VoiceProjectOption> projects,
    required String currency,
    required String languageHint,
    void Function(double progress)? onUploadProgress,
  }) async {
    final uploaded = await _uploadService.uploadVoiceExpenseAudio(
      userId: userId,
      localFilePath: localAudioPath,
      onProgress: onUploadProgress,
    );
    final result = await _cloudFunctionService.processVoiceExpense(
      storagePath: uploaded.storagePath,
      projects: projects.map((project) => project.toMap()).toList(),
      currency: currency,
      languageHint: languageHint,
    );
    return VoiceExpenseParseResponse.fromMap(result);
  }

  Future<String?> saveConfirmedVoiceExpense({
    required String workspaceId,
    required String projectId,
    required String projectName,
    required double amount,
    required String currency,
    required String category,
    required String notes,
    required String transcript,
    required String source,
    required String storagePath,
    required DateTime date,
  }) {
    return _expenseSaveService.saveVoiceExpense(
      workspaceId: workspaceId,
      projectId: projectId,
      projectName: projectName,
      amount: amount,
      currency: currency,
      category: category,
      date: date,
      notes: notes,
      transcript: transcript,
      source: source,
      storagePath: storagePath,
    );
  }
}

final voiceExpenseRepositoryProvider = Provider<VoiceExpenseRepository>((ref) {
  return VoiceExpenseRepository(
    uploadService: ref.watch(storageUploadServiceProvider),
    cloudFunctionService: ref.watch(cloudFunctionServiceProvider),
    expenseSaveService: ref.watch(expenseSaveServiceProvider),
  );
});
