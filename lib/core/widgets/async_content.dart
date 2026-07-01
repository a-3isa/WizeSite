import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stale-while-revalidate rendering for [AsyncValue]s.
///
/// Reduces loading indication across the app by:
///  * Keeping the last successful data on screen during reloads/refreshes
///    instead of flashing a skeleton again.
///  * Keeping stale data visible when a *refresh* fails (a transient error on
///    top of previously-loaded data), instead of replacing content with an
///    error view.
///
/// Only the genuine first load (no data yet) shows [loading], and only a
/// first-load failure (no data to fall back on) shows [error].
extension AsyncContentX<T> on AsyncValue<T> {
  Widget whenStale({
    required Widget Function(T data) data,
    required Widget Function() loading,
    required Widget Function(Object error, StackTrace stackTrace) error,
  }) {
    return when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      skipError: false,
      data: data,
      loading: loading,
      error: (err, stackTrace) {
        final cached = value;
        if (cached != null) {
          return data(cached);
        }
        return error(err, stackTrace);
      },
    );
  }
}
