import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

class VoiceAiDisclosureStore {
  VoiceAiDisclosureStore({Box<String>? prefsBox}) : _prefsBox = prefsBox;

  static const prefsBoxName = 'app_prefs';
  static const acceptedKey = 'voice_ai_disclosure_accepted';

  final Box<String>? _prefsBox;

  Box<String>? get _box {
    if (_prefsBox != null) {
      return _prefsBox;
    }
    if (!Hive.isBoxOpen(prefsBoxName)) {
      return null;
    }
    return Hive.box<String>(prefsBoxName);
  }

  bool get hasAccepted => _box?.get(acceptedKey) == '1';

  Future<void> accept() async {
    await _box?.put(acceptedKey, '1');
  }
}

final voiceAiDisclosureStoreProvider = Provider<VoiceAiDisclosureStore>(
  (ref) => VoiceAiDisclosureStore(),
);
