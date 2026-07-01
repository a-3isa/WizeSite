import 'dart:async';

import 'package:buildtrack_app/app/app.dart';
import 'package:buildtrack_app/core/services/firebase_initializer.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      final coldStart = Stopwatch()..start();
      WidgetsFlutterBinding.ensureInitialized();
      await Hive.initFlutter();
      await Hive.openBox<String>('app_prefs');
      await Hive.openBox<String>('offline_actions');
      await FirebaseInitializer.ensureInitialized();
      await FirebaseCrashlytics.instance.log('app.start firebase_initialized');
      coldStart.stop();
      await FirebaseCrashlytics.instance.log(
        'app.start bootstrap_complete duration_ms=${coldStart.elapsedMilliseconds}',
      );

      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      runApp(const ProviderScope(child: BuildozerApp()));
    },
    (error, stack) async {
      try {
        await FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          fatal: true,
        );
      } catch (_) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
    },
  );
}
