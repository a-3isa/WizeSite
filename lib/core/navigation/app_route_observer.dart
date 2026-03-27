import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

mixin RouteAutoRefreshMixin<T extends ConsumerStatefulWidget> on ConsumerState<T>
    implements RouteAware {
  RouteObserver<ModalRoute<dynamic>>? _observer;
  ModalRoute<dynamic>? _route;
  bool _didInitialVisibleCall = false;

  FutureOr<void> onScreenVisible();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute) {
      return;
    }
    final observer = _findNavigatorRouteObserver();
    if (observer == null) {
      if (!_didInitialVisibleCall) {
        _didInitialVisibleCall = true;
        unawaited(Future<void>.sync(onScreenVisible));
      }
      return;
    }
    if (_observer == observer && _route == route) {
      return;
    }
    if (_observer != null) {
      _observer!.unsubscribe(this);
    }
    _observer = observer;
    _route = route;
    _observer!.subscribe(this, route);
    if (!_didInitialVisibleCall) {
      _didInitialVisibleCall = true;
      unawaited(Future<void>.sync(onScreenVisible));
    }
  }

  @override
  void dispose() {
    _observer?.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {
    if (_didInitialVisibleCall) {
      return;
    }
    _didInitialVisibleCall = true;
    unawaited(Future<void>.sync(onScreenVisible));
  }

  @override
  void didPopNext() {
    unawaited(Future<void>.sync(onScreenVisible));
  }

  @override
  void didPop() {}

  @override
  void didPushNext() {}

  RouteObserver<ModalRoute<dynamic>>? _findNavigatorRouteObserver() {
    final observers = Navigator.of(context).widget.observers;
    for (final observer in observers) {
      if (observer is RouteObserver) {
        return observer as RouteObserver<ModalRoute<dynamic>>;
      }
    }
    return null;
  }
}
