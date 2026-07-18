import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// True when [subscription] entitles the workspace to create additional
/// workspaces. Mirrors the gate used by [EntitlementGuardService] elsewhere
/// in the app: Pro tier and an active-or-trial status.
bool workspaceCreationEntitled(SubscriptionState subscription) {
  return subscription.tier == PlanTier.pro && subscription.isActiveOrTrial;
}

/// Opens the v2 workspace switcher as a bottom sheet: lists the user's
/// workspaces (tap to switch) and a "Create workspace" action gated on Pro.
Future<void> showWorkspaceSwitcherSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _WorkspaceSwitcherSheet(),
  );
}

class _WorkspaceSwitcherSheet extends ConsumerWidget {
  const _WorkspaceSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final activeWorkspaceId = ref.watch(activeWorkspaceIdProvider);
    final workspaces =
        ref.watch(userWorkspaceSummariesProvider).value ??
        const <WorkspaceSummary>[];
    final subscription =
        ref.watch(currentSubscriptionStreamProvider).value ??
        SubscriptionState.free();
    final entitled = workspaceCreationEntitled(subscription);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: EdgeInsets.all(t.cardPad),
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.rXl),
          boxShadow: t.shadowMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(
              l10n.t('switchWorkspace'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: t.text,
              ),
            ),
            SizedBox(height: t.gap),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final workspace in workspaces)
                      Padding(
                        padding: EdgeInsets.only(bottom: t.gap),
                        child: _WorkspaceTile(
                          key: ValueKey('qa_workspace_tile_${workspace.id}'),
                          workspace: workspace,
                          active: workspace.id == activeWorkspaceId,
                          onTap: () => _switchWorkspace(context, ref, workspace.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: t.gap),
            BuildButton(
              key: const Key('qa_workspace_create'),
              label: l10n.t('createWorkspace'),
              icon: Icons.add_business_outlined,
              variant: BuildButtonVariant.soft,
              size: BuildButtonSize.lg,
              full: true,
              onPressed: () => _onCreateWorkspaceTap(
                context,
                ref,
                entitled: entitled,
                sourceWorkspaceId: activeWorkspaceId,
              ),
            ),
            if (!entitled) ...[
              const SizedBox(height: 8),
              Text(
                l10n.t('createWorkspaceUpsell'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: t.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _switchWorkspace(
    BuildContext context,
    WidgetRef ref,
    String workspaceId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final activeWorkspaceIdNotifier = ref.read(
      activeWorkspaceIdProvider.notifier,
    );
    final workspaceService = ref.read(workspaceMutationServiceProvider);
    final previousWorkspaceId = activeWorkspaceIdNotifier.state;

    navigator.pop();
    if (workspaceId == previousWorkspaceId) {
      return;
    }
    activeWorkspaceIdNotifier.state = workspaceId;
    try {
      final persistedWorkspaceId = await workspaceService.setActiveWorkspace(
        workspaceId: workspaceId,
      );
      if (persistedWorkspaceId.isNotEmpty &&
          persistedWorkspaceId != workspaceId) {
        activeWorkspaceIdNotifier.state = persistedWorkspaceId;
      }
    } catch (error) {
      activeWorkspaceIdNotifier.state = previousWorkspaceId;
      messenger.showSnackBar(
        SnackBar(content: Text(appErrorMessage(l10n, error))),
      );
    }
  }

  void _onCreateWorkspaceTap(
    BuildContext context,
    WidgetRef ref, {
    required bool entitled,
    required String? sourceWorkspaceId,
  }) {
    final navigator = Navigator.of(context);
    if (!entitled || sourceWorkspaceId == null || sourceWorkspaceId.isEmpty) {
      final router = GoRouter.of(context);
      navigator.pop();
      router.push(AppRoutes.subscriptionPlans);
      return;
    }
    navigator.pop();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _CreateWorkspaceSheet(sourceWorkspaceId: sourceWorkspaceId),
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.workspace,
    required this.active,
    required this.onTap,
    super.key,
  });

  final WorkspaceSummary workspace;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    return BuildCard(
      onTap: onTap,
      color: active ? t.accentSoft : t.surface2,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Avatar(label: workspace.name, size: 36),
          SizedBox(width: t.gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workspace.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                Text(
                  _roleLabel(l10n, workspace.role),
                  style: TextStyle(fontSize: 12.5, color: t.textMuted),
                ),
              ],
            ),
          ),
          if (active)
            Icon(Icons.check_circle, color: t.accent, size: 20)
          else
            Icon(Icons.business_outlined, color: t.textFaint, size: 20),
        ],
      ),
    );
  }

  static String _roleLabel(AppLocalizations l10n, String role) {
    switch (role) {
      case 'owner':
        return l10n.t('ownerRole');
      case 'admin':
        return l10n.t('adminRole');
      case 'accountingApproved':
        return l10n.t('accountingApprovedRole');
      case 'entryOnly':
        return l10n.t('entryOnlyRole');
      case 'member':
      default:
        return l10n.t('memberRole');
    }
  }
}

class _CreateWorkspaceSheet extends ConsumerStatefulWidget {
  const _CreateWorkspaceSheet({required this.sourceWorkspaceId});

  final String sourceWorkspaceId;

  @override
  ConsumerState<_CreateWorkspaceSheet> createState() =>
      _CreateWorkspaceSheetState();
}

class _CreateWorkspaceSheetState extends ConsumerState<_CreateWorkspaceSheet> {
  final _nameController = TextEditingController();
  String _currency = 'EGP';
  bool _saving = false;
  String? _error;

  static const _currencies = [
    DropdownMenuEntry(value: 'EGP', label: 'EGP'),
    DropdownMenuEntry(value: 'USD', label: 'USD'),
    DropdownMenuEntry(value: 'SAR', label: 'SAR'),
    DropdownMenuEntry(value: 'AED', label: 'AED'),
    DropdownMenuEntry(value: 'KWD', label: 'KWD'),
    DropdownMenuEntry(value: 'QAR', label: 'QAR'),
    DropdownMenuEntry(value: 'BHD', label: 'BHD'),
    DropdownMenuEntry(value: 'OMR', label: 'OMR'),
    DropdownMenuEntry(value: 'JOD', label: 'JOD'),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.t('workspaceNameEmptyError'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final workspaceId = await ref
          .read(workspaceMutationServiceProvider)
          .createWorkspace(
            sourceWorkspaceId: widget.sourceWorkspaceId,
            workspaceName: name,
            defaultCurrency: _currency,
          );
      ref.read(activeWorkspaceIdProvider.notifier).state = workspaceId;
      ref.invalidate(userWorkspaceSummariesProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = appErrorMessage(l10n, error));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: EdgeInsets.all(t.cardPad),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(t.rXl),
            boxShadow: t.shadowMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text(
                l10n.t('createWorkspaceTitle'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: t.text,
                ),
              ),
              SizedBox(height: t.gap),
              BuildTextField(
                key: const Key('qa_new_workspace_name'),
                label: l10n.t('workspaceNameTitle'),
                controller: _nameController,
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: t.gap),
              BelowDropdownField<String>(
                label: l10n.t('currency'),
                value: _currency,
                entries: _currencies,
                onSelected: (value) {
                  if (value != null) {
                    setState(() => _currency = value);
                  }
                },
              ),
              if (_error != null) ...[
                SizedBox(height: t.gap),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
              SizedBox(height: t.gap),
              BuildButton(
                key: const Key('qa_new_workspace_save'),
                label: l10n.t('createWorkspace'),
                size: BuildButtonSize.lg,
                full: true,
                onPressed: _saving ? null : _create,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
