import 'dart:io';

import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/self_hosted_rpc_transport.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

abstract interface class ProfileRepository {
  Future<String> uploadProfilePhoto({
    required String userId,
    required String localFilePath,
  });

  Future<void> updateProfile({
    required String fullName,
    String? photoUrl,
    String? defaultCurrency,
    bool? riskAlertsEnabled,
  });
}

/// Profile photos go to `POST /v1/files` (spec 004); the returned link is the
/// permanent public avatar URL. Profile edits are queued RPCs.
class SelfHostedProfileRepository implements ProfileRepository {
  SelfHostedProfileRepository(
    this._transport,
    this._mutationService, {
    BackendConfig config = BackendConfig.fromEnvironment,
  }) : _config = config;

  final SelfHostedRpcTransport _transport;
  final WorkspaceMutationService _mutationService;
  final BackendConfig _config;

  @override
  Future<String> uploadProfilePhoto({
    required String userId,
    required String localFilePath,
  }) async {
    final source = File(localFilePath);
    if (!await source.exists()) {
      throw const ProfileRepositoryException(
        'Selected profile image was not found.',
      );
    }
    try {
      final uploaded = await _transport.uploadFile(
        kind: 'profile-photos',
        bytes: await source.readAsBytes(),
        fileName: 'avatar.jpg',
        contentType: 'image/jpeg',
        idempotencyKey: const Uuid().v4(),
      );
      return _config.publicFileUri('${uploaded['storagePath']}').toString();
    } on CallableClientException catch (error) {
      throw ProfileRepositoryException(error.message);
    }
  }

  @override
  Future<void> updateProfile({
    required String fullName,
    String? photoUrl,
    String? defaultCurrency,
    bool? riskAlertsEnabled,
  }) {
    return _mutationService.updateUserProfile(
      fullName: fullName,
      photoUrl: photoUrl,
      defaultCurrency: defaultCurrency,
      riskAlertsEnabled: riskAlertsEnabled,
    );
  }
}

class ProfileRepositoryException implements Exception {
  const ProfileRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return SelfHostedProfileRepository(
    ref.watch(selfHostedRpcTransportProvider),
    ref.watch(workspaceMutationServiceProvider),
  );
});
