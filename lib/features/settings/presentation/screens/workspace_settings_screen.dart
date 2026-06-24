import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('memberships')
      .where('workspaceId', isEqualTo: workspaceId)
      .snapshots()
      .asyncMap((membershipSnap) async {
        final members = await Future.wait(
          membershipSnap.docs.map((doc) async {
            final data = doc.data();
            final userId = '${data['userId'] ?? ''}';
            final userSnap = await firestore
                .collection('users')
                .doc(userId)
                .get();
            final user = userSnap.data() ?? const <String, dynamic>{};
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
  final members = ref.watch(teamMembersProvider).valueOrNull ?? const [];
  final match = members.where((member) => member.userId == userId);
  return match.isEmpty ? null : match.first.role;
});

final workspaceNameProvider = StreamProvider<String>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return Stream.value('');
  }
  return ref
      .watch(firestoreProvider)
      .collection('workspaces')
      .doc(workspaceId)
      .snapshots()
      .map((snap) => '${snap.data()?['name'] ?? ''}'.trim());
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
          .read(firestoreProvider)
          .collection('workspaces')
          .doc(workspaceId)
          .update({
            'name': nextName,
            'updatedAt': FieldValue.serverTimestamp(),
          });
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
    final membersAsync = ref.watch(teamMembersProvider);
    final currentUserRole = ref.watch(currentUserRoleProvider);
    final workspaceName = ref.watch(workspaceNameProvider).valueOrNull ?? '';
    final canManage = currentUserRole == 'owner';

    return AppBackScope(
      fallbackRoute: AppRoutes.settings,
      child: Scaffold(
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
              Text(
                l10n.t('inviteMember'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: l10n.t('inviteByEmail')),
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
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _inviting ? null : _invite,
                child: _inviting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.t('inviteMember')),
              ),
              const SizedBox(height: 24),
            ],
            Text(
              l10n.t('workspaceCrewTitle'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
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
    return Card(
      child: ListTile(
        leading: const Icon(Icons.business_outlined),
        title: Text(l10n.t('workspaceNameTitle')),
        subtitle: Text(name),
        trailing: canRename
            ? IconButton(
                tooltip: l10n.t('renameWorkspace'),
                onPressed: onRename,
                icon: const Icon(Icons.edit_outlined),
              )
            : null,
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
    final displayName = member.fullName.isEmpty
        ? member.email.split('@').first
        : member.fullName;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: member.photoUrl.isEmpty
              ? null
              : NetworkImage(member.photoUrl),
          child: member.photoUrl.isEmpty ? Text(_initials(displayName)) : null,
        ),
        title: Text(displayName),
        subtitle: Text(member.email),
        trailing: canManage
            ? Row(
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
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              )
            : Text(roleLabel),
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
