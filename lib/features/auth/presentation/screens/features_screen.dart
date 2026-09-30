import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class _FeatureItem {
  const _FeatureItem({
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
  });

  final IconData icon;
  final String titleKey;
  final String subtitleKey;
}

class FeaturesScreen extends StatelessWidget {
  const FeaturesScreen({super.key});

  static const _features = [
    _FeatureItem(
      icon: Icons.smartphone_rounded,
      titleKey: 'featureMobileFirstTitle',
      subtitleKey: 'featureMobileFirstSubtitle',
    ),
    _FeatureItem(
      icon: Icons.mic_rounded,
      titleKey: 'featureVoiceExpenseTitle',
      subtitleKey: 'featureVoiceExpenseSubtitle',
    ),
    _FeatureItem(
      icon: Icons.pie_chart_rounded,
      titleKey: 'featureProfitabilityTitle',
      subtitleKey: 'featureProfitabilitySubtitle',
    ),
    _FeatureItem(
      icon: Icons.translate_rounded,
      titleKey: 'featureLocalizationTitle',
      subtitleKey: 'featureLocalizationSubtitle',
    ),
    _FeatureItem(
      icon: Icons.picture_as_pdf_rounded,
      titleKey: 'featurePdfReportsTitle',
      subtitleKey: 'featurePdfReportsSubtitle',
    ),
    _FeatureItem(
      icon: Icons.offline_bolt_rounded,
      titleKey: 'featureOfflineTitle',
      subtitleKey: 'featureOfflineSubtitle',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      backgroundColor: t.accent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 32, 24, 20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: t.onAccent.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.construction_rounded,
                      color: t.onAccent,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.t('appName'),
                    style: theme.textTheme.headlineLarge?.copyWith(
                      color: t.onAccent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.t('tagline'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: t.onAccent.withValues(alpha: 0.92),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(t.rXl),
                  ),
                  boxShadow: t.shadowMd,
                ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          20,
                          24,
                          20,
                          12,
                        ),
                        child: Text(
                          l10n.t('whatYouGet'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: context.tokens.text.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          itemCount: _features.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final feature = _features[index];
                            return _FeatureCard(
                              icon: feature.icon,
                              title: l10n.t(feature.titleKey),
                              subtitle: l10n.t(feature.subtitleKey),
                              iconColor: context.tokens.accent,
                            );
                          },
                        ),
                      ),
                      // CTA
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          20,
                          8,
                          20,
                          24,
                        ),
                        child: FilledButton(
                          onPressed: () {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (context.mounted) {
                                context.push(AppRoutes.onboarding);
                              }
                            });
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: t.accent,
                            foregroundColor: t.onAccent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(t.rMd),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.t('getStarted'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: isRTL ? 0 : 8),
                              Icon(
                                isRTL
                                    ? Icons.arrow_back_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 20,
                              ),
                              SizedBox(width: isRTL ? 8 : 0),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: iconColor.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.tokens.text,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.tokens.text.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
