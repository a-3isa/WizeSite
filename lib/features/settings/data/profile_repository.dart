import 'dart:io';

import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  FirebaseProfileRepository(this._storage, this._mutationService);

  final FirebaseStorage _storage;
  final WorkspaceMutationService _mutationService;

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
  );
});
