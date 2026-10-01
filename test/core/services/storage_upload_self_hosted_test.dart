import 'dart:convert';
import 'dart:io';

import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/services/self_hosted_rpc_transport.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Self-hosted uploads (spec 004, T081): POST /v1/files, multipart, same
/// headers as RPCs, a stable idempotency key, and no download URL returned.
void main() {
  late Directory dir;
  late File photo;
  late List<http.BaseRequest> requests;
  late List<String> bodies;

  StorageUploadService service(Future<http.Response> Function() respond) {
    final client = MockClient.streaming((request, bodyStream) async {
      requests.add(request);
      bodies.add(latin1.decode(await bodyStream.toBytes()));
      final response = await respond();
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    });
    return StorageUploadService(
      SelfHostedRpcTransport(
        config: const BackendConfig(
          apiBaseUrl: 'https://api.example.com/',
          syncUrl: 'https://sync.example.com',
        ),
        httpClient: client,
        idToken: ({required bool forceRefresh}) async => 'id-token',
        appCheckToken: () async => 'app-check',
      ),
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('upload_self_hosted_test_');
    photo = File('${dir.path}${Platform.pathSeparator}receipt.jpg');
    await photo.writeAsBytes([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
    requests = [];
    bodies = [];
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('uploads to /v1/files with kind, file and the given key', () async {
    final uploads = service(
      () async => http.Response(
        jsonEncode({
          'storagePath': 'attachments/u1/abc.jpg',
          'contentType': 'image/jpeg',
          'sizeBytes': 7,
          'sha256': 'x',
        }),
        201,
      ),
    );
    final uploaded = await uploads.uploadAttachment(
      userId: 'u1',
      localFilePath: photo.path,
      fileName: 'إيصال.jpg',
      idempotencyKey: 'pending_1',
    );
    expect(uploaded.storagePath, 'attachments/u1/abc.jpg');
    expect(uploaded.downloadUrl, '');
    expect(uploaded.size, 7);
    expect(uploaded.contentType, 'image/jpeg');

    final request = requests.single;
    expect(request.url.toString(), 'https://api.example.com/v1/files');
    expect(request.headers['Authorization'], 'Bearer id-token');
    expect(request.headers['X-Firebase-AppCheck'], 'app-check');
    expect(request.headers['X-Idempotency-Key'], 'pending_1');
    expect(bodies.single, contains('name="kind"\r\n\r\nattachments'));
    expect(bodies.single.toLowerCase(), contains('content-type: image/jpeg'));
  });

  test('a refused upload is not retryable; a server error is', () async {
    final refused = service(
      () async => http.Response(
        jsonEncode({
          'error': {
            'code': 'invalid-argument',
            'message': 'Unsupported file type',
          },
        }),
        400,
      ),
    );
    await expectLater(
      refused.uploadAttachment(userId: 'u1', localFilePath: photo.path),
      throwsA(
        isA<StorageUploadException>()
            .having((e) => e.message, 'message', 'Unsupported file type')
            .having((e) => e.retryable, 'retryable', false),
      ),
    );
    final down = service(() async => http.Response('', 503));
    await expectLater(
      down.uploadAttachment(userId: 'u1', localFilePath: photo.path),
      throwsA(
        isA<StorageUploadException>().having(
          (e) => e.retryable,
          'retryable',
          true,
        ),
      ),
    );
  });
}
