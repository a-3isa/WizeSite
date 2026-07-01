import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keys grouped by the review-pack surfaces that must be fully localized.
/// Each key must exist in the English keyset and have a distinct Arabic
/// translation (not the raw English fallback produced by the `..._en` spread).
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

void main() {
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

  test('arabic accounting labels are translated and not raw fallback text', () {
    final l10n = AppLocalizations(const Locale('ar'));

    expect(l10n.t('weeklySummary'), 'ملخص أسبوعي');
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
