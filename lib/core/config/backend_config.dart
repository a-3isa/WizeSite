/// Backend endpoints (spec 004): the self-hosted API and the sync service.
///
/// Builds default to the VPS endpoints; another environment passes both:
///
/// ```sh
/// flutter run --dart-define=API_BASE_URL=https://api.example.com \
///             --dart-define=SYNC_URL=https://sync.example.com
/// ```
class BackendConfig {
  const BackendConfig({required this.apiBaseUrl, required this.syncUrl});

  static const fromEnvironment = BackendConfig(
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api.buildozer.dpdns.org',
    ),
    syncUrl: String.fromEnvironment(
      'SYNC_URL',
      defaultValue: 'https://sync.buildozer.dpdns.org',
    ),
  );

  /// Base URL of the self-hosted RPC API, without a trailing slash.
  final String apiBaseUrl;

  /// Base URL of the PowerSync service.
  final String syncUrl;

  String get _base => apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Uri rpcUri(String functionName) => Uri.parse('$_base/v1/rpc/$functionName');

  /// File uploads (contracts/files-api.md).
  Uri get filesUri => Uri.parse('$_base/v1/files');

  /// Permanent public link for an uploaded profile photo.
  Uri publicFileUri(String storagePath) =>
      Uri.parse('$_base/v1/public/$storagePath');
}
