import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/localization/locale_controller.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  String? _selectedLanguageCode;

  static const _slides = <(IconData, String, String)>[
    (
      Icons.work,
      'onboardingTrackProjectsTitle',
      'onboardingTrackProjectsSubtitle',
    ),
    (
      Icons.receipt_long,
      'onboardingAddExpensesTitle',
      'onboardingAddExpensesSubtitle',
    ),
    (
      Icons.trending_up,
      'onboardingKnowProfitTitle',
      'onboardingKnowProfitSubtitle',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentLocale = ref.watch(localeControllerProvider);
    _selectedLanguageCode ??= currentLocale.languageCode;
    final totalPages = _slides.length + 1;

    // Onboarding paging is pinned to LTR so the swipe/advance direction is the
    // same in every language. Page *content* still renders in the ambient
    // direction, restored inside the builders below.
    final contentDirection = Directionality.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => context.go(AppRoutes.login),
                child: Text(l10n.t('skip')),
              ),
            ),
            Expanded(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: totalPages,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Directionality(
                        textDirection: contentDirection,
                        child: _LanguageStep(
                          selectedLanguageCode: _selectedLanguageCode!,
                          onLanguageChanged: (languageCode) {
                            setState(
                              () => _selectedLanguageCode = languageCode,
                            );
                          },
                        ),
                      );
                    }

                    final slide = _slides[index - 1];
                    return Directionality(
                      textDirection: contentDirection,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              slide.$1,
                              size: 88,
                              color: context.tokens.accent,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              l10n.t(slide.$2),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 12),
                            Text(l10n.t(slide.$3), textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // Dots follow the page order, so they are pinned to LTR too.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  totalPages,
                  (idx) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: _index == idx ? 20 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: _index == idx
                          ? context.tokens.accent
                          : context.tokens.surface3,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (_index == 0) {
                      ref
                          .read(localeControllerProvider.notifier)
                          .setLocale(Locale(_selectedLanguageCode!));
                    }

                    if (_index < totalPages - 1) {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                    } else {
                      context.go(AppRoutes.login);
                    }
                  },
                  child: Text(
                    _index < totalPages - 1
                        ? l10n.t('next')
                        : l10n.t('continue'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageStep extends StatelessWidget {
  const _LanguageStep({
    required this.selectedLanguageCode,
    required this.onLanguageChanged,
  });

  final String selectedLanguageCode;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.language, size: 88, color: context.tokens.accent),
          const SizedBox(height: 24),
          Text(
            l10n.t('chooseLanguageTitle'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.t('chooseLanguageSubtitle'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          _LanguageOption(
            selected: selectedLanguageCode == 'en',
            title: l10n.t('englishLanguage'),
            subtitle: 'English',
            onTap: () => onLanguageChanged('en'),
          ),
          const SizedBox(height: 12),
          _LanguageOption(
            selected: selectedLanguageCode == 'ar',
            title: l10n.t('arabicLanguage'),
            subtitle: 'العربية',
            onTap: () => onLanguageChanged('ar'),
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.rMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.rMd),
          border: Border.all(
            color: selected ? t.accent : t.borderStrong,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? t.accent : t.textFaint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
