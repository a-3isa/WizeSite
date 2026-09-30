import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const remoteConfigMinSupportedBuildKey = 'min_supported_build';
const remoteConfigVoiceAiEnabledKey = 'voice_ai_enabled';

class AppRemoteConfig {
  const AppRemoteConfig({
    this.minSupportedBuild = 0,
    this.voiceAiEnabled = true,
  });

  final int minSupportedBuild;
  final bool voiceAiEnabled;
}

final appRemoteConfigProvider = FutureProvider<AppRemoteConfig>((ref) {
  return const AppRemoteConfigLoader().load();
});

/// Loads kill switches and the minimum supported build from Remote Config.
/// Fail-open: defaults keep the app usable if Firebase is unavailable.
class AppRemoteConfigLoader {
  const AppRemoteConfigLoader();

  Future<AppRemoteConfig> load() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setDefaults(const {
        remoteConfigMinSupportedBuildKey: 0,
        remoteConfigVoiceAiEnabledKey: true,
      });
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 5),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await remoteConfig.fetchAndActivate();
      return AppRemoteConfig(
        minSupportedBuild: remoteConfig.getInt(
          remoteConfigMinSupportedBuildKey,
        ),
        voiceAiEnabled: remoteConfig.getBool(remoteConfigVoiceAiEnabledKey),
      );
    } catch (_) {
      return const AppRemoteConfig();
    }
  }
}
