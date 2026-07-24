import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/widgets/app_search_field.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Above this many projects, the sheet grows a live search box.
const int _projectSearchThreshold = 6;

/// Opens the dashboard's project filter as a bottom sheet, mirroring
/// [showWorkspaceSwitcherSheet]: "All Projects" first, then every project in
/// [projects], with a live search field once there are more than
/// [_projectSearchThreshold] projects to scroll through.
Future<void> showProjectSelectorSheet(
  BuildContext context,
  WidgetRef ref, {
  required List<Project> projects,
  required String? selectedProjectId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProjectSelectorSheet(
      projects: projects,
      selectedProjectId: selectedProjectId,
    ),
  );
}

class _ProjectSelectorSheet extends ConsumerStatefulWidget {
  const _ProjectSelectorSheet({
    required this.projects,
    required this.selectedProjectId,
  });

  final List<Project> projects;
  final String? selectedProjectId;

  @override
  ConsumerState<_ProjectSelectorSheet> createState() =>
      _ProjectSelectorSheetState();
}

class _ProjectSelectorSheetState extends ConsumerState<_ProjectSelectorSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _select(String? projectId) {
    ref.read(selectedDashboardProjectIdProvider.notifier).state = projectId;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final showSearch = widget.projects.length > _projectSearchThreshold;
    final query = _query.trim().toLowerCase();
    final showAllProjectsTile = query.isEmpty;
    final filteredProjects = query.isEmpty
        ? widget.projects
        : widget.projects
              .where((project) => project.name.toLowerCase().contains(query))
              .toList();
    final hasNoMatches = query.isNotEmpty && filteredProjects.isEmpty;

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
              l10n.t('selectProject'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: t.text,
              ),
            ),
            SizedBox(height: t.gap),
            if (showSearch) ...[
              AppSearchField(
                key: const Key('qa_project_selector_search'),
                controller: _searchController,
                labelText: l10n.t('searchProjects'),
                onChanged: (value) => setState(() => _query = value),
              ),
              SizedBox(height: t.gap),
            ],
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showAllProjectsTile)
                      Padding(
                        padding: EdgeInsets.only(bottom: t.gap),
                        child: _ProjectTile(
                          key: const Key('qa_project_tile_all'),
                          icon: Icons.public_outlined,
                          label: l10n.t('allProjects'),
                          selected: widget.selectedProjectId == null,
                          onTap: () => _select(null),
                        ),
                      ),
                    for (final project in filteredProjects)
                      Padding(
                        padding: EdgeInsets.only(bottom: t.gap),
                        child: _ProjectTile(
                          key: ValueKey('qa_project_tile_${project.id}'),
                          icon: Icons.work_outline,
                          label: project.name,
                          selected: project.id == widget.selectedProjectId,
                          onTap: () => _select(project.id),
                        ),
                      ),
                    if (hasNoMatches)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: t.gap),
                        child: Text(
                          l10n.t('noProjectsMatchSearch'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: t.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return BuildCard(
      onTap: onTap,
      color: selected ? t.accentSoft : t.surface2,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: t.accent, size: 22),
          SizedBox(width: t.gap),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
          if (selected)
            Icon(Icons.check_circle, color: t.accent, size: 20)
          else
            Icon(Icons.chevron_right, color: t.textFaint, size: 20),
        ],
      ),
    );
  }
}
