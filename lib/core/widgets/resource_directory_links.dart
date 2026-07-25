import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart'
    show workersProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Directory navigation for the four resource types (Workers, Contractors,
/// Equipment, Transport). Workers is given prominence with a live count (from
/// the same unlimited `workersProvider` stream used elsewhere); the other three
/// route through the shared entity-directory system, which has no cheap
/// unlimited count stream, so they intentionally show no number rather than one
/// capped by a page size.
///
/// Lives on the More tab (the resource hub). Kept out of the Home dashboard,
/// which stays focused on financial/operational stats.
class ResourceDirectoryLinks extends ConsumerWidget {
  const ResourceDirectoryLinks({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final workersCount = ref.watch(workersProvider).value?.length;
    final workersLabel = workersCount != null
        ? l10n.t(
            'resourceCountLabel',
            params: {'label': l10n.t('workers'), 'count': '$workersCount'},
          )
        : l10n.t('workers');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ResourceCard(
          qaKey: const Key('qa_resource_workers'),
          icon: Icons.engineering_outlined,
          label: workersLabel,
          color: context.tokens.warning,
          onTap: () => context.push(AppRoutes.workers),
          prominent: true,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ResourceCard(
                qaKey: const Key('qa_resource_contractors'),
                icon: Icons.handyman_outlined,
                label: l10n.t('contractorsDirectory'),
                color: context.tokens.accent,
                onTap: () => context.push(AppRoutes.contractorsDirectory),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ResourceCard(
                qaKey: const Key('qa_resource_equipment'),
                icon: Icons.construction_outlined,
                label: l10n.t('equipmentDirectory'),
                color: context.tokens.income,
                onTap: () => context.push(AppRoutes.equipmentDirectory),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ResourceCard(
                qaKey: const Key('qa_resource_transport'),
                icon: Icons.local_shipping_outlined,
                label: l10n.t('transportDirectory'),
                color: context.tokens.expense,
                onTap: () =>
                    context.push(AppRoutes.transportProvidersDirectory),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.qaKey,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.prominent = false,
  });

  final Key qaKey;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: Material(
        key: qaKey,
        color: color.withValues(alpha: prominent ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            // Vertical padding sized so even the compact (non-prominent)
            // cards clear the 48dp minimum touch target without changing the
            // icon/text sizing that gives them their compact visual weight.
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: prominent ? 14 : 10,
              vertical: prominent ? 14 : 16,
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: prominent ? 26 : 18),
                SizedBox(width: prominent ? 12 : 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: prominent ? 16 : 12,
                      color: prominent ? color : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
