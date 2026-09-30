import 'dart:io';
import 'dart:typed_data';

import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/services/attachment_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Attachment _attachment(String path) => Attachment(
  id: 'a1',
  fileName: 'receipt.pdf',
  storagePath: path,
  contentType: 'application/pdf',
  uploadedAt: DateTime.utc(2026, 6, 1),
);

void main() {
  late Directory root;
  late List<String> opened;
  late List<String> launched;
  late int downloads;

  AttachmentCacheService service({int statusCode = 200, int maxBytes = 1000}) {
    return AttachmentCacheService(
      cacheRoot: () async => root,
      httpClient: MockClient((request) async {
        downloads++;
        return http.Response.bytes(
          Uint8List.fromList(List.filled(100, 7)),
          statusCode,
        );
      }),
      openFile: (path) async {
        opened.add(path);
        return true;
      },
      openUrl: (url) async {
        launched.add(url);
        return true;
      },
      maxBytes: maxBytes,
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('attachment_cache_test_');
    opened = [];
    launched = [];
    downloads = 0;
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('first open downloads and caches; second open works offline', () async {
    final cache = service();
    final attachment = _attachment('ws_1/expenses/e1/receipt.pdf');
    var resolves = 0;
    Future<String> resolve() async {
      resolves++;
      return 'https://api.example.test/v1/files/signed/x';
    }

    await cache.open(
      workspaceId: 'ws_1',
      attachment: attachment,
      resolveUrl: resolve,
    );
    // Offline: resolving would throw, but the cached copy is used.
    await cache.open(
      workspaceId: 'ws_1',
      attachment: attachment,
      resolveUrl: () async => throw const SocketException('offline'),
    );

    expect(downloads, 1);
    expect(resolves, 1);
    expect(opened, hasLength(2));
    expect(opened.first, endsWith('.pdf'));
    expect(File(opened.first).lengthSync(), 100);
    expect(launched, isEmpty);
  });

  test('failed download falls back to opening the URL', () async {
    final cache = service(statusCode: 403);
    await cache.open(
      workspaceId: 'ws_1',
      attachment: _attachment('ws_1/p/receipt.pdf'),
      resolveUrl: () async => 'https://api.example.test/x',
    );
    expect(launched, ['https://api.example.test/x']);
    expect(root.listSync(), isEmpty);
  });

  test('evicts oldest files past the size cap, keeping the new one', () async {
    final cache = service(maxBytes: 250);
    for (final name in ['a', 'b', 'c']) {
      await cache.download(
        'ws_1',
        _attachment('ws_1/$name.pdf'),
        'https://api.example.test/$name',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final names = root.listSync().map((e) => e.uri.pathSegments.last).toList();
    expect(names, hasLength(2));
    expect(names.any((n) => n.endsWith('c.pdf')), isTrue);
  });

  test('cache file names are safe and bounded', () {
    final long = 'ws/${'x' * 300}/file.jpg';
    final name = AttachmentCacheService.cacheFileName('ws', _attachment(long));
    expect(name.length, lessThanOrEqualTo(150));
    expect(name, endsWith('file.jpg'));
    expect(
      AttachmentCacheService.cacheFileName('ws', _attachment('a/../b c.pdf')),
      isNot(contains('/')),
    );
  });
}
