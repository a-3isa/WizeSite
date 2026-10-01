import 'dart:io';

import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/self_hosted_rpc_transport.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
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

class FirebaseProfileRepository implements ProfileRepository {
  FirebaseProfileRepository(
    this._storage,
    this._mutationService, {
    SelfHostedRpcTransport? selfHostedTransport,
    BackendConfig config = BackendConfig.fromEnvironment,
  }) : _selfHosted = selfHostedTransport,
       _config = config;

  final FirebaseStorage _storage;
  final WorkspaceMutationService _mutationService;

  /// Self-hosted builds (spec 004): the photo goes to `POST /v1/files` and the
  /// returned link is the permanent public avatar URL.
  final SelfHostedRpcTransport? _selfHosted;
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

    final selfHosted = _selfHosted;
    if (selfHosted != null) {
      try {
        final uploaded = await selfHosted.uploadFile(
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

    final ref = _storage.ref('profile-photos/$userId/avatar.jpg');
    await ref.putFile(
      source,
      SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: <String, String>{'uploadedBy': userId},
      ),
    );
    return ref.getDownloadURL();
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
  return FirebaseProfileRepository(
    FirebaseStorage.instance,
    ref.watch(workspaceMutationServiceProvider),
    selfHostedTransport: ref.watch(selfHostedRpcTransportProvider),
  );
});
