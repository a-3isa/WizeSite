import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

/// A single active filter shown as a removable token.
class ActiveFilter {
  const ActiveFilter({required this.id, required this.label});

  /// Stable identifier reported back to [ActiveFilterBar.onRemove].
  final String id;

  /// Human-readable, already-localized text shown on the token.
  final String label;
}

/// A removable filter chip. Tapping the trailing affordance removes the filter.
class FilterToken extends StatelessWidget {
  const FilterToken({required this.label, required this.onRemove, super.key});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final removeLabel = l10n.t('removeFilter');

    return Container(
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      decoration: BoxDecoration(
        color: AppColors.constructionOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.constructionOrange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.constructionOrange,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: removeLabel,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 16,
            icon: const Icon(Icons.close, color: AppColors.constructionOrange),
          ),
        ],
      ),
    );
  }
}

/// Shows the currently-applied filters as removable tokens, with an optional
/// clear-all action when more than one filter is active.
///
/// Renders nothing when no filters are active. This is distinct from grouping
/// controls: it only reflects and removes active filters.
class ActiveFilterBar extends StatelessWidget {
  const ActiveFilterBar({
    required this.filters,
    required this.onRemove,
    this.onClearAll,
    super.key,
  });

  final List<ActiveFilter> filters;

  /// Called with the [ActiveFilter.id] of the token to remove.
  final ValueChanged<String> onRemove;

  /// When provided and more than one filter is active, a clear-all control is
  /// shown.
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final showClearAll = onClearAll != null && filters.length > 1;

    return Semantics(
      label: l10n.t('activeFilters'),
      container: true,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final filter in filters)
            FilterToken(
              key: ValueKey('filter_${filter.id}'),
              label: filter.label,
              onRemove: () => onRemove(filter.id),
            ),
          if (showClearAll)
            TextButton.icon(
              onPressed: onClearAll,
              icon: const Icon(Icons.clear_all, size: 18),
              label: Text(l10n.t('clearAllFilters')),
              style: TextButton.styleFrom(
                foregroundColor: context.tokens.textMuted,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}
