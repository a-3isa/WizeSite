import 'dart:convert';
import 'dart:io';

import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/services/self_hosted_rpc_transport.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/settings/data/profile_repository.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorage extends Mock implements FirebaseStorage {}

class _MockMutations extends Mock implements WorkspaceMutationService {}

/// Self-hosted profile photos (spec 004): uploaded as kind `profile-photos`,
/// shown from the permanent public avatar URL.
void main() {
  test('uploads the photo and returns its public link', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_test_');
    addTearDown(() => dir.delete(recursive: true));
    final photo = File('${dir.path}${Platform.pathSeparator}me.jpg');
    await photo.writeAsBytes([0xff, 0xd8, 0xff]);
    String? kind;
    const config = BackendConfig(
      apiBaseUrl: 'https://api.example.com/',
      syncUrl: 'https://sync.example.com',
    );
    final repo = FirebaseProfileRepository(
      _MockStorage(),
      _MockMutations(),
      config: config,
      selfHostedTransport: SelfHostedRpcTransport(
        config: config,
        httpClient: MockClient.streaming((request, body) async {
          kind =
              latin1
                  .decode(await body.toBytes())
                  .contains('name="kind"\r\n\r\nprofile-photos')
              ? 'profile-photos'
              : 'other';
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'storagePath': 'profile-photos/u1/abc.jpg',
                  'contentType': 'image/jpeg',
                  'sizeBytes': 3,
                  'sha256': 'x',
                }),
              ),
            ),
            201,
          );
        }),
        idToken: ({required bool forceRefresh}) async => 'id-token',
        appCheckToken: () async => 'app-check',
      ),
    );
    final url = await repo.uploadProfilePhoto(
      userId: 'u1',
      localFilePath: photo.path,
    );
    expect(kind, 'profile-photos');
    expect(url, 'https://api.example.com/v1/public/profile-photos/u1/abc.jpg');
  });
}
