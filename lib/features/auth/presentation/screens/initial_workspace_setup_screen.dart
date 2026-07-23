import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class InitialWorkspaceSetupScreen extends ConsumerStatefulWidget {
  const InitialWorkspaceSetupScreen({super.key});

  @override
  ConsumerState<InitialWorkspaceSetupScreen> createState() =>
      _InitialWorkspaceSetupScreenState();
}

class _InitialWorkspaceSetupScreenState
    extends ConsumerState<InitialWorkspaceSetupScreen> {
  final _workspaceNameController = TextEditingController();
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
    _workspaceNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final workspaceName = _workspaceNameController.text.trim();
    if (workspaceName.isEmpty) {
      setState(() => _error = l10n.t('workspaceNameEmptyError'));
      return;
    }
    if (workspaceId == null || workspaceId.isEmpty) {
      setState(() => _error = l10n.t('noWorkspaceSelected'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(workspaceMutationServiceProvider)
          .completeInitialWorkspaceSetup(
            workspaceId: workspaceId,
            workspaceName: workspaceName,
            defaultCurrency: _currency,
          );
      ref.invalidate(currentUserSettingsProvider);
      ref.invalidate(userWorkspaceSummariesProvider);
      if (mounted) {
        context.go(AppRoutes.dashboard);
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
    return Scaffold(
      backgroundColor: context.tokens.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.business_rounded,
                    size: 56,
                    color: context.tokens.accent,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.t('setupWorkspaceTitle'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.tokens.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('setupWorkspaceSubtitle'),
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: context.tokens.textMuted),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _workspaceNameController,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.t('workspaceNameTitle'),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: context.tokens.expense),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.t('save')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
