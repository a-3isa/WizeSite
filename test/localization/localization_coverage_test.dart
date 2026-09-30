import 'dart:io';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keys grouped by the review-pack surfaces that must be fully localized.
/// Each key must exist in the English keyset and have a distinct Arabic
/// translation (not the English text that `t()` falls back to).
const Map<String, List<String>> _reviewPackKeyGroups = {
  'navigation': [
    'navigationHomeTab',
    'navigationAddTab',
    'navigationProjectsTab',
  ],
  'unread notifications': [
    'unreadNotificationsCount',
    'markAllRead',
    'viewAllNotifications',
  ],
  'loading and recovery states': [
    'loadingContent',
    'somethingWentWrong',
    'tryAgain',
    'recoverableErrorTitle',
  ],
  'voice countdown and playback': [
    'voiceCountdownRemaining',
    'voiceRecordingInProgress',
    'voicePlayRecording',
    'voiceRerecord',
    'voiceProcessing',
  ],
  'filter removal': ['removeFilter', 'clearAllFilters', 'activeFilters'],
  // Optional project budget. The localization system falls back to English
  // silently, so a missing Arabic entry produces no error — it just ships
  // English to Arabic users. This group is the only thing that catches it.
  'optional project budget': [
    'noContractValueTitle',
    'noContractValueBody',
    'setContractValue',
    'contractValueRequiredForPayments',
    'removePaymentsBeforeClearingContract',
  ],
  'bulk archive': [
    'selectionMode',
    'archiveSelected',
    'bulkArchiveConfirm',
    'bulkArchivePartialFailure',
  ],
  'report scope and export': [
    'reportScope',
    'reportDateRange',
    'printReport',
    'shareReport',
    'shareChart',
  ],
  'worker status': [
    'workerStatusActive',
    'workerStatusInactive',
    'workerStatusTerminated',
  ],
  'plan comparison': [
    'comparePlans',
    'planRecommended',
    'planFeatureIncluded',
    'planFeatureNotIncluded',
  ],
  'settings help and legal': [
    'appVersion',
    'helpAndSupport',
    'privacyPolicy',
    'termsOfService',
    'runDiagnostics',
  ],
  'sync outcomes': [
    'syncStatus',
    'syncPending',
    'syncFailed',
    'syncResolvedNewerKept',
    'retrySync',
  ],
};

/// Keys whose Arabic value is legitimately identical to the English one:
/// brand names, symbols, and pure placeholder format strings.
const Set<String> _arabicIdenticalAllowlist = {
  'appName', // brand name
  'loadingShort', // '...'
  'none', // '-'
  'projectDateWithValue', // '{project} | {date}'
  'resourceCountLabel', // '{label} ({count})'
};

void main() {
  test('every Arabic value is actually translated, not English text', () {
    final en = AppLocalizations.localizedValues['en']!;
    final ar = AppLocalizations.localizedValues['ar']!;

    // Strip placeholders like {count} before judging whether text is English.
    final placeholder = RegExp(r'\{[a-zA-Z0-9_]+\}');
    final arabicScript = RegExp(r'[؀-ۿ]');
    final latinWord = RegExp(r'[A-Za-z]{2,}');

    final untranslated = <String>[];
    for (final entry in ar.entries) {
      if (_arabicIdenticalAllowlist.contains(entry.key)) continue;
      final value = entry.value.replaceAll(placeholder, ' ');
      if (arabicScript.hasMatch(value)) continue;
      if (!latinWord.hasMatch(value)) continue;
      untranslated.add('${entry.key} = "${entry.value}"');
    }

    expect(
      untranslated,
      isEmpty,
      reason:
          'These Arabic entries still hold English text, so the app shows '
          'English while the locale is ar:\n  ${untranslated.join('\n  ')}',
    );
    // Guard the guard: the allowlist must not accumulate stale entries.
    for (final key in _arabicIdenticalAllowlist) {
      expect(en, contains(key), reason: 'Stale allowlist entry "$key"');
    }
  });

  test('all supported locales contain the full key set', () {
    final values = AppLocalizations.localizedValues;
    final enKeys = values['en']!.keys.toSet();

    for (final locale in AppLocalizations.supportedLocales) {
      final localeValues = values[locale.languageCode];
      expect(
        localeValues,
        isNotNull,
        reason: 'Missing map for locale ${locale.languageCode}',
      );
      expect(
        localeValues!.keys.toSet(),
        enKeys,
        reason: 'Locale ${locale.languageCode} does not match keyset',
      );
    }
  });

  test('every literal key passed to t() in lib/ is defined', () {
    // An undefined key makes t() return the key itself (e.g. 'worker'), which
    // renders as English in the Arabic UI with no error.
    final defined = AppLocalizations.requiredKeys;
    final call = RegExp(r"""\.t\(\s*'([A-Za-z0-9_]+)'""");
    final missing = <String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final match in call.allMatches(file.readAsStringSync())) {
        final key = match.group(1)!;
        if (!defined.contains(key)) missing.add('$key (${file.path})');
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'Keys used in code but missing from the localization maps:\n  '
          '${missing.join('\n  ')}',
    );
  });

  test('arabic accounting labels are translated and not raw fallback text', () {
    final l10n = AppLocalizations(const Locale('ar'));

    expect(l10n.t('weeklySummary'), 'آخر 7 أيام');
    expect(l10n.t('purpose'), 'الغرض');
    expect(l10n.t('paymentStatus'), 'حالة الدفع');
    expect(l10n.t('entityNameOptional'), 'اسم الكيان (اختياري)');
    expect(l10n.t('selectAttachments'), 'اختيار المرفقات');
    expect(l10n.t('attachment'), 'مرفق');
    expect(l10n.paymentStatusLabel('unpaid'), 'غير مدفوع');
    expect(l10n.expenseCategoryLabel('labor'), 'عمالة');
    expect(l10n.expenseCategoryLabel('storage'), 'تخزين');
  });

  group('review-pack surfaces are fully localized', () {
    final en = AppLocalizations.localizedValues['en']!;
    final ar = AppLocalizations.localizedValues['ar']!;
    final requiredKeys = AppLocalizations.requiredKeys;

    for (final entry in _reviewPackKeyGroups.entries) {
      test('${entry.key} keys exist and are translated to Arabic', () {
        for (final key in entry.value) {
          expect(
            requiredKeys,
            contains(key),
            reason: 'Missing English key "$key" for ${entry.key}',
          );
          expect(
            (en[key] ?? '').trim(),
            isNotEmpty,
            reason: 'English value for "$key" must not be empty',
          );
          expect(
            (ar[key] ?? '').trim(),
            isNotEmpty,
            reason: 'Arabic value for "$key" must not be empty',
          );
          expect(
            ar[key],
            isNot(equals(en[key])),
            reason: 'Arabic value for "$key" must not be the English fallback',
          );
        }
      });
    }
  });
}
