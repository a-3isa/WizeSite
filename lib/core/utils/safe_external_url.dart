import 'package:url_launcher/url_launcher.dart';

const Set<String> defaultExternalUrlSchemes = {'http', 'https', 'mailto'};

Uri? safeExternalUriOrNull(
  String? raw, {
  Set<String> allowedSchemes = defaultExternalUrlSchemes,
}) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme) {
    return null;
  }

  final scheme = uri.scheme.toLowerCase();
  if (!allowedSchemes.contains(scheme)) {
    return null;
  }
  if ((scheme == 'http' || scheme == 'https') && uri.host.trim().isEmpty) {
    return null;
  }
  if (scheme == 'mailto' && uri.path.trim().isEmpty) {
    return null;
  }
  return uri;
}

String? safeExternalUrlOrNull(
  String? raw, {
  Set<String> allowedSchemes = defaultExternalUrlSchemes,
}) {
  return safeExternalUriOrNull(raw, allowedSchemes: allowedSchemes)?.toString();
}

Future<bool> launchSafeExternalUrl(
  String? raw, {
  LaunchMode mode = LaunchMode.externalApplication,
  Set<String> allowedSchemes = defaultExternalUrlSchemes,
}) async {
  final uri = safeExternalUriOrNull(raw, allowedSchemes: allowedSchemes);
  if (uri == null) {
    return false;
  }
  return launchUrl(uri, mode: mode);
}
