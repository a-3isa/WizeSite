import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

class TeamManagementScreen extends ConsumerStatefulWidget {
  const TeamManagementScreen({super.key});

  @override
  ConsumerState<TeamManagementScreen> createState() =>
      _TeamManagementScreenState();
}

class _TeamManagementScreenState extends ConsumerState<TeamManagementScreen> {
  final _emailController = TextEditingController();
  String _role = 'member';
  bool _inviting = false;
  String? _error;

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
        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(content: Text(l10n.t('inviteMember'))),
        // );
      }
    } on CallableClientException catch (error) {
      if (error.code == 'failed-precondition' && mounted) {
        context.push('${AppRoutes.subscriptionLimit}?limit=teamMembers');
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _inviting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final membersAsync = ref.watch(teamMembersProvider);
    final currentUserRole = ref.watch(currentUserRoleProvider);
    final canInvite = currentUserRole == 'owner';

    return AppBackScope(
      fallbackRoute: AppRoutes.settings,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('teamManagement'),
          fallbackRoute: AppRoutes.settings,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (canInvite) ...[
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
              DropdownButtonFormField<String>(
                initialValue: _role,
                items: [
                  DropdownMenuItem(
                    value: 'member',
                    child: Text(l10n.t('memberRole')),
                  ),
                  DropdownMenuItem(
                    value: 'owner',
                    child: Text(l10n.t('ownerRole')),
                  ),
                ],
                onChanged: (value) => setState(() => _role = value ?? 'member'),
                decoration: InputDecoration(labelText: l10n.t('role')),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
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
              l10n.t('teamMembersTitle'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            membersAsync.when(
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
                        (member) => Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundImage: member.photoUrl.isEmpty
                                  ? null
                                  : NetworkImage(member.photoUrl),
                              child: member.photoUrl.isEmpty
                                  ? Text(
                                      _initials(
                                        member.fullName.isEmpty
                                            ? member.email
                                            : member.fullName,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              member.fullName.isEmpty
                                  ? member.email.split('@').first
                                  : member.fullName,
                            ),
                            subtitle: Text(member.email),
                            trailing: Text(
                              member.role == 'owner'
                                  ? l10n.t('ownerRole')
                                  : l10n.t('memberRole'),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
              error: (error, _) => Center(child: Text(error.toString())),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String value) {
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
