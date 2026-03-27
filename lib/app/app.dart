import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/localization/locale_controller.dart';
import 'package:buildtrack_app/app/router.dart';
import 'package:buildtrack_app/app/theme/app_theme.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BuildozerApp extends ConsumerWidget {
  const BuildozerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);

    return AppBootstrapScope(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: AppLocalizations(locale).t('appName'),
        locale: locale,
        theme: AppTheme.light(locale),
        routerConfig: ref.watch(appRouterProvider),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }
}
