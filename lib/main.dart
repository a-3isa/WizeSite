import 'dart:async';

import 'package:buildtrack_app/app/app.dart';
import 'package:buildtrack_app/core/services/firebase_initializer.dart';
import 'package:buildtrack_app/core/storage/hive_boxes.dart';
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
      hiveEncryptionCipher = await loadOrCreateHiveCipher();
      await openEncryptedBox<String>('app_prefs');
      await openEncryptedBox<String>('offline_actions');
      await openEncryptedBox<String>('pending_attachments');
      await persistHiveEncryptionReady();
      await FirebaseInitializer.ensureInitialized();
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );
      await FirebaseCrashlytics.instance.log('app.start firebase_initialized');
      coldStart.stop();
      await FirebaseCrashlytics.instance.log(
        'app.start bootstrap_complete duration_ms=${coldStart.elapsedMilliseconds}',
      );

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
        return true;
      };

      runApp(const ProviderScope(child: BuildozerApp()));
    },
      (error, stack) async {
      try {
        await FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          fatal: false,
        );
      } catch (_) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
    },
  );
}
