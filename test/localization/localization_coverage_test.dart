import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
