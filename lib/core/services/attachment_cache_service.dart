import 'dart:io';

import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/utils/safe_external_url.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps opened attachments on the device so they can be viewed again
/// offline (spec 004, T055). Files live in the OS cache directory, are keyed
/// by workspace + storage path, and are cleared on sign-out.
class AttachmentCacheService {
  AttachmentCacheService({
    Future<Directory> Function()? cacheRoot,
    http.Client? httpClient,
    Future<bool> Function(String path)? openFile,
    Future<bool> Function(String url)? openUrl,
    this.maxBytes = 250 * 1024 * 1024,
  }) : _cacheRoot = cacheRoot ?? defaultCacheRoot,
       _http = httpClient ?? http.Client(),
       _openFile = openFile ?? _openWithPlatform,
       _openUrl = openUrl ?? launchSafeExternalUrl;

  final Future<Directory> Function() _cacheRoot;
  final http.Client _http;
  final Future<bool> Function(String path) _openFile;
  final Future<bool> Function(String url) _openUrl;

  /// Oldest files are evicted once the cache grows past this size.
  final int maxBytes;

  static Future<Directory> defaultCacheRoot() async {
    final base = await getApplicationCacheDirectory();
    return Directory(p.join(base.path, 'attachment_cache'));
  }

  static Future<bool> _openWithPlatform(String path) async {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done;
  }

  /// Removes every cached attachment. Called on sign-out so the next account
  /// never sees the previous one's files.
  static Future<void> clearDefault() async {
    try {
      final root = await defaultCacheRoot();
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {
      // Sign-out must not fail on local cleanup.
    }
  }

  /// File name for an attachment: readable, filesystem-safe, keeps the
  /// extension, and stays short for long storage paths.
  static String cacheFileName(String workspaceId, Attachment attachment) {
    final key = '$workspaceId/${attachment.storagePath.trim()}';
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.length <= 150) return safe;
    return '${_fnv1a(key)}_${safe.substring(safe.length - 120)}';
  }

  static String _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<File> _fileFor(String workspaceId, Attachment attachment) async {
    final root = await _cacheRoot();
    return File(p.join(root.path, cacheFileName(workspaceId, attachment)));
  }

  /// The cached copy, if this attachment was opened before on this device.
  Future<File?> cachedFile(String workspaceId, Attachment attachment) async {
    final file = await _fileFor(workspaceId, attachment);
    return await file.exists() ? file : null;
  }

  /// Downloads [url] into the cache (atomically) and returns the file.
  Future<File> download(
    String workspaceId,
    Attachment attachment,
    String url,
  ) async {
    final file = await _fileFor(workspaceId, attachment);
    await file.parent.create(recursive: true);
    final response = await _http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw HttpException(
        'Attachment download failed (${response.statusCode})',
        uri: Uri.parse(url),
      );
    }
    final partial = File('${file.path}.part');
    await partial.writeAsBytes(response.bodyBytes, flush: true);
    await partial.rename(file.path);
    await _evict(keep: file.path);
    return file;
  }

  Future<void> _evict({required String keep}) async {
    final root = await _cacheRoot();
    final files = <File, FileStat>{
      for (final entity in root.listSync().whereType<File>())
        entity: entity.statSync(),
    };
    var total = files.values.fold<int>(0, (sum, stat) => sum + stat.size);
    final oldestFirst = files.keys.toList()
      ..sort((a, b) => files[a]!.modified.compareTo(files[b]!.modified));
    for (final file in oldestFirst) {
      if (total <= maxBytes) break;
      if (file.path == keep) continue;
      total -= files[file]!.size;
      await file.delete();
    }
  }

  /// Opens an attachment: the cached copy when there is one (works offline),
  /// otherwise resolves a URL, caches the file and opens it. If caching fails
  /// the URL is opened directly, as before.
  Future<void> open({
    required String workspaceId,
    required Attachment attachment,
    required Future<String> Function() resolveUrl,
  }) async {
    final cached = await cachedFile(workspaceId, attachment);
    if (cached != null && await _openFile(cached.path)) return;

    final url = await resolveUrl();
    File? file;
    try {
      file = await download(workspaceId, attachment, url);
    } catch (_) {
      file = null;
    }
    if (file != null && await _openFile(file.path)) return;
    if (!await _openUrl(url)) {
      throw Exception('Could not open attachment.');
    }
  }
}

final attachmentCacheServiceProvider = Provider<AttachmentCacheService>(
  (ref) => AttachmentCacheService(),
);
