import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:flutter/material.dart';
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

/// Shows the one-time AI disclosure unless it was already accepted. Voice
/// recording and pasted receipt text share one acceptance (feature 005).
Future<bool> ensureAiDisclosureAccepted(
  BuildContext context,
  VoiceAiDisclosureStore store,
) async {
  if (store.hasAccepted) {
    return true;
  }
  final l10n = AppLocalizations.of(context);
  final accepted = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(l10n.t('voiceAiDisclosureTitle')),
      content: Text(l10n.t('voiceAiDisclosureMessage')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.t('notNow')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.t('voiceAiDisclosureContinue')),
        ),
      ],
    ),
  );
  if (accepted != true) {
    return false;
  }
  await store.accept();
  return true;
}
