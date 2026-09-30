/// Build-time backend selection (spec 004).
///
/// Production builds pass no defines and keep using Firebase (Cloud Functions,
/// Firestore, Storage). Staging builds of the self-hosted backend pass both:
///
/// ```sh
/// flutter run --dart-define=API_BASE_URL=https://api.example.com \
///             --dart-define=SYNC_URL=https://sync.example.com
/// ```
class BackendConfig {
  const BackendConfig({required this.apiBaseUrl, required this.syncUrl});

  static const fromEnvironment = BackendConfig(
    apiBaseUrl: String.fromEnvironment('API_BASE_URL'),
    syncUrl: String.fromEnvironment('SYNC_URL'),
  );

  /// Base URL of the self-hosted RPC API, without a trailing slash.
  final String apiBaseUrl;

  /// Base URL of the PowerSync service.
  final String syncUrl;

  /// True when this build talks to the self-hosted backend instead of Firebase.
  bool get useSelfHostedBackend => apiBaseUrl.trim().isNotEmpty;

  String get _base => apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Uri rpcUri(String functionName) => Uri.parse('$_base/v1/rpc/$functionName');

  /// File uploads (contracts/files-api.md).
  Uri get filesUri => Uri.parse('$_base/v1/files');
}
