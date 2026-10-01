import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TeamMemberView {
  const TeamMemberView({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.photoUrl,
    required this.role,
  });

  final String userId;
  final String fullName;
  final String email;
  final String photoUrl;
  final String role;
}

final teamMembersProvider = StreamProvider<List<TeamMemberView>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }

  final source = ref.watch(docSourceProvider);
  return source
      .watch(DocQuery('memberships', equals: {'workspaceId': workspaceId}))
      .asyncMap((memberships) async {
        final members = await Future.wait(
          memberships.map((doc) async {
            final data = doc.data;
            final userId = '${data['userId'] ?? ''}';
            final userDoc = await source.getDoc('users', userId);
            final user = userDoc?.data ?? const <String, dynamic>{};
            return TeamMemberView(
              userId: userId,
              fullName: '${user['fullName'] ?? ''}'.trim(),
              email: '${user['email'] ?? ''}'.trim(),
              photoUrl: '${user['photoUrl'] ?? ''}'.trim(),
              role: '${data['role'] ?? 'member'}'.trim(),
            );
          }),
        );
        members.sort((a, b) {
          if (a.role == b.role) {
            return a.email.compareTo(b.email);
          }
          return a.role == 'owner' ? -1 : 1;
        });
        return members;
      });
});

final currentUserRoleProvider = Provider<String?>((ref) {
  final userId = ref.watch(activeUserIdProvider);
  final members = ref.watch(teamMembersProvider).value ?? const [];
  final match = members.where((member) => member.userId == userId);
  return match.isEmpty ? null : match.first.role;
});

final workspaceNameProvider = StreamProvider<String>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return Stream.value('');
  }
  return ref
      .watch(docSourceProvider)
      .watchDoc('workspaces', workspaceId)
      .map((doc) => '${doc?.data['name'] ?? ''}'.trim());
});

class WorkspaceSettingsScreen extends ConsumerStatefulWidget {
  const WorkspaceSettingsScreen({super.key});

  @override
  ConsumerState<WorkspaceSettingsScreen> createState() =>
      _WorkspaceSettingsScreenState();
}

class _WorkspaceSettingsScreenState
    extends ConsumerState<WorkspaceSettingsScreen> {
  final _emailController = TextEditingController();
  String _role = 'member';
  bool _inviting = false;
  String? _error;

  static const _roles = [
    'owner',
    'admin',
    'accountingApproved',
    'member',
    'entryOnly',
  ];

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final email = _emailController.text.trim().toLowerCase();
    if (workspaceId == null || workspaceId.isEmpty) {
      setState(() => _error = l10n.t('noWorkspaceSelected'));
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = l10n.t('authInvalidEmailFormat'));
      return;
    }

    setState(() {
      _inviting = true;
      _error = null;
    });
    try {
      await ref
          .read(workspaceMutationServiceProvider)
          .inviteMemberByEmail(
            workspaceId: workspaceId,
            email: email,
            role: _role,
          );
      if (mounted) {
        _emailController.clear();
      }
    } on CallableClientException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = appErrorMessage(l10n, error));
      }
    } finally {
      if (mounted) {
        setState(() => _inviting = false);
      }
    }
  }

  Future<void> _renameWorkspace(String currentName) async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    if (workspaceId == null || workspaceId.isEmpty) {
      return;
    }
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => _RenameWorkspaceDialog(currentName: currentName),
    );
    if (nextName == null || nextName == currentName) {
      return;
    }
    if (nextName.isEmpty) {
      _showSnack(l10n.t('workspaceNameEmptyError'));
      return;
    }
    try {
      await ref
          .read(workspaceMutationServiceProvider)
          .updateWorkspaceName(workspaceId: workspaceId, name: nextName);
      ref.invalidate(userWorkspaceSummariesProvider);
      ref.invalidate(workspaceNameProvider);
    } catch (error) {
      _showSnack(appErrorMessage(l10n, error));
    }
  }

  Future<void> _updateRole(TeamMemberView member, String role) async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    if (workspaceId == null || workspaceId.isEmpty || role == member.role) {
      return;
    }
    try {
      await ref
          .read(workspaceMutationServiceProvider)
          .updateWorkspaceMemberRole(
            workspaceId: workspaceId,
            userId: member.userId,
            role: role,
          );
      ref.invalidate(teamMembersProvider);
    } catch (error) {
      _showSnack(appErrorMessage(l10n, error));
    }
  }

  Future<void> _removeMember(TeamMemberView member) async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    if (workspaceId == null || workspaceId.isEmpty) {
      return;
    }
    try {
      await ref
          .read(workspaceMutationServiceProvider)
          .removeWorkspaceMember(
            workspaceId: workspaceId,
            userId: member.userId,
          );
      ref.invalidate(teamMembersProvider);
    } catch (error) {
      _showSnack(appErrorMessage(l10n, error));
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final membersAsync = ref.watch(teamMembersProvider);
    final currentUserRole = ref.watch(currentUserRoleProvider);
    final workspaceName = ref.watch(workspaceNameProvider).value ?? '';
    final canManage = currentUserRole == 'owner';

    return AppBackScope(
      fallbackRoute: AppRoutes.settings,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('settingsWorkspace'),
          fallbackRoute: AppRoutes.settings,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _WorkspaceNameTile(
              name: workspaceName.isEmpty
                  ? l10n.t('settingsWorkspace')
                  : workspaceName,
              canRename: canManage,
              onRename: () => _renameWorkspace(workspaceName),
            ),
            const SizedBox(height: 24),
            if (canManage) ...[
              _SectionLabel(l10n.t('inviteMember')),
              const SizedBox(height: 12),
              BuildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BuildTextField(
                      label: l10n.t('inviteByEmail'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_inviting,
                    ),
                    const SizedBox(height: 12),
                    BelowDropdownField<String>(
                      label: l10n.t('role'),
                      value: _role,
                      entries: _roles
                          .map(
                            (role) => DropdownMenuEntry(
                              value: role,
                              label: _roleLabel(l10n, role),
                            ),
                          )
                          .toList(growable: false),
                      onSelected: (value) =>
                          setState(() => _role = value ?? 'member'),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 12),
              if (_inviting)
                const Center(child: CircularProgressIndicator())
              else
                BuildButton(
                  label: l10n.t('inviteMember'),
                  size: BuildButtonSize.lg,
                  full: true,
                  onPressed: _invite,
                ),
              const SizedBox(height: 24),
            ],
            _SectionLabel(l10n.t('workspaceCrewTitle')),
            const SizedBox(height: 12),
            membersAsync.whenStale(
              data: (members) {
                if (members.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text(l10n.t('noTeamMembersYet'))),
                  );
                }
                return Column(
                  children: members
                      .map(
                        (member) => _MemberCard(
                          member: member,
                          canManage: canManage,
                          roleLabel: _roleLabel(l10n, member.role),
                          roles: _roles,
                          roleLabelBuilder: (role) => _roleLabel(l10n, role),
                          onRoleChanged: (role) => _updateRole(member, role),
                          onRemove: () => _removeMember(member),
                        ),
                      )
                      .toList(),
                );
              },
              error: (error, _) =>
                  Center(child: Text(appErrorMessage(l10n, error))),
              loading: () => const AppLoadingSkeleton(lineCount: 4),
            ),
          ],
        ),
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

class _RenameWorkspaceDialog extends StatefulWidget {
  const _RenameWorkspaceDialog({required this.currentName});

  final String currentName;

  @override
  State<_RenameWorkspaceDialog> createState() => _RenameWorkspaceDialogState();
}

class _RenameWorkspaceDialogState extends State<_RenameWorkspaceDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.t('renameWorkspace')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.t('workspaceNameTitle')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(l10n.t('save')),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      label,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: t.text,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.expenseSoft, borderRadius: t.radiusMd),
      child: Text(message, style: TextStyle(color: t.expense, fontSize: 13.5)),
    );
  }
}

class _WorkspaceNameTile extends StatelessWidget {
  const _WorkspaceNameTile({
    required this.name,
    required this.canRename,
    required this.onRename,
  });

  final String name;
  final bool canRename;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    return BuildCard(
      child: Row(
        children: [
          Icon(Icons.business_outlined, color: t.textMuted, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('workspaceNameTitle'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: t.textMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ],
            ),
          ),
          if (canRename)
            IconButton(
              tooltip: l10n.t('renameWorkspace'),
              onPressed: onRename,
              icon: Icon(Icons.edit_outlined, color: t.accent),
            ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.canManage,
    required this.roleLabel,
    required this.roles,
    required this.roleLabelBuilder,
    required this.onRoleChanged,
    required this.onRemove,
  });

  final TeamMemberView member;
  final bool canManage;
  final String roleLabel;
  final List<String> roles;
  final String Function(String role) roleLabelBuilder;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final displayName = member.fullName.isEmpty
        ? member.email.split('@').first
        : member.fullName;
    return BuildCard(
      margin: const EdgeInsetsDirectional.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: t.accentSoft,
            backgroundImage: member.photoUrl.isEmpty
                ? null
                : NetworkImage(member.photoUrl),
            child: member.photoUrl.isEmpty
                ? Text(
                    _initials(displayName),
                    style: TextStyle(
                      color: t.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  member.email,
                  style: TextStyle(fontSize: 13, color: t.textMuted),
                ),
              ],
            ),
          ),
          if (canManage)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: member.role,
                  underline: const SizedBox.shrink(),
                  items: roles
                      .map(
                        (role) => DropdownMenuItem(
                          value: role,
                          child: Text(roleLabelBuilder(role)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      onRoleChanged(value);
                    }
                  },
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context).t('delete'),
                  onPressed: onRemove,
                  icon: Icon(Icons.remove_circle_outline, color: t.expense),
                ),
              ],
            )
          else
            Text(roleLabel, style: TextStyle(fontSize: 13, color: t.textMuted)),
        ],
      ),
    );
  }

  static String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
