import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';

/// Records the current screen name as a Crashlytics custom key on every
/// navigation event so that crash reports always show which screen the
/// user was on.
class CrashlyticsRouteObserver extends NavigatorObserver {
  CrashlyticsRouteObserver();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _track(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _track(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _track(newRoute);

  void _track(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    FirebaseCrashlytics.instance.setCustomKey('current_route', name);
  }
}
