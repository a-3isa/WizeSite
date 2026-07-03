import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

/// Shared async-state primitives used across feature screens so loading,
/// recoverable error, and empty states look and behave consistently and stay
/// accessible (semantic labels, non-color affordances, retry CTAs).
///
/// These widgets never render raw exception text. Callers must sanitize
/// failures through `appErrorMessage` (see `core/utils/app_error_messages.dart`)
/// before passing a message here.

/// Animated placeholder shown while content is loading.
class AppLoadingSkeleton extends StatefulWidget {
  const AppLoadingSkeleton({
    super.key,
    this.lineCount = 3,
    this.semanticsLabel,
    this.padding = const EdgeInsets.all(16),
  });

  /// Number of skeleton bars to render.
  final int lineCount;

  /// Accessible label announced for the loading region. Falls back to the
  /// localized `loadingContent` string.
  final String? semanticsLabel;

  final EdgeInsetsGeometry padding;

  @override
  State<AppLoadingSkeleton> createState() => _AppLoadingSkeletonState();
}

class _AppLoadingSkeletonState extends State<AppLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = widget.semanticsLabel ?? l10n.t('loadingContent');
    final lines = widget.lineCount.clamp(1, 12);

    return Semantics(
      label: label,
      liveRegion: true,
      child: Padding(
        padding: widget.padding,
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.35, end: 0.85).animate(_controller),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < lines; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == lines - 1 ? 0 : 12),
                  child: Container(
                    height: 14,
                    width: i.isEven ? double.infinity : 180,
                    decoration: BoxDecoration(
                      color: context.tokens.surface3,
                      borderRadius: BorderRadius.circular(8),
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

/// Error card with a sanitized message and an optional retry affordance.
class AppRecoverableError extends StatelessWidget {
  const AppRecoverableError({
    super.key,
    required this.message,
    this.onRetry,
    this.title,
    this.retryLabel,
  });

  /// Already-localized, sanitized message. Never pass raw exception text.
  final String message;

  /// When non-null, a retry CTA is rendered and wired to this callback.
  final VoidCallback? onRetry;

  /// Optional heading. Falls back to the localized `recoverableErrorTitle`.
  final String? title;

  /// Optional retry button label. Falls back to the localized `tryAgain`.
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final heading = title ?? l10n.t('recoverableErrorTitle');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.danger),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  heading,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: AppColors.danger)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.white,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh, size: 18),
                    const SizedBox(width: 6),
                    Text(retryLabel ?? l10n.t('tryAgain')),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Empty-state card with a message and an optional call-to-action.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.semanticsLabel,
  });

  final String message;
  final IconData icon;

  /// CTA label. A button is only rendered when both [actionLabel] and
  /// [onAction] are provided.
  final String? actionLabel;
  final VoidCallback? onAction;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.tokens.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: context.tokens.textMuted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.tokens.textMuted),
          ),
          if (hasAction) ...[
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );

    // The message Text already exposes an accessible label; only add an
    // explicit container label when the caller overrides it.
    if (semanticsLabel == null) return card;
    return Semantics(label: semanticsLabel, container: true, child: card);
  }
}
