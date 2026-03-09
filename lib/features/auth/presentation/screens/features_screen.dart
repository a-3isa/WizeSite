import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class _FeatureItem {
  const _FeatureItem({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;
}

class FeaturesScreen extends StatelessWidget {
  const FeaturesScreen({super.key});

  static const _features = [
    _FeatureItem(
      icon: Icons.smartphone_rounded,
      title: 'Mobile-first operation',
      subtitle: 'Manage projects and expenses from the field',
    ),
    _FeatureItem(
      icon: Icons.mic_rounded,
      title: 'Voice expense entry',
      subtitle: 'Log costs hands-free with speech',
    ),
    _FeatureItem(
      icon: Icons.pie_chart_rounded,
      title: 'Real-time profitability',
      subtitle: 'See project health and margins live',
    ),
    _FeatureItem(
      icon: Icons.translate_rounded,
      title: 'Arabic / English + RTL',
      subtitle: 'Full localization and layout support',
    ),
    _FeatureItem(
      icon: Icons.picture_as_pdf_rounded,
      title: 'PDF reports',
      subtitle: 'Export and share professional reports',
    ),
    _FeatureItem(
      icon: Icons.offline_bolt_rounded,
      title: 'Offline-safe actions',
      subtitle: 'Work without connection, sync when back',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE85D04), Color(0xFFFF7A00), Color(0xFFFF9E33)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Hero
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 32, 24, 20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.construction_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'BuildTrack',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.t('tagline'),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              // Content card
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, -4),
                      ),
                    ],
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
                          'What you get',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.darkGray.withValues(alpha: 0.8),
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
                              title: feature.title,
                              subtitle: feature.subtitle,
                              iconColor: AppColors.constructionOrange,
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
                          onPressed: () => context.go(AppRoutes.onboarding),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.constructionOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
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
                width: 44,
                height: 44,
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
                        color: AppColors.textDark,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.darkGray.withValues(alpha: 0.8),
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
