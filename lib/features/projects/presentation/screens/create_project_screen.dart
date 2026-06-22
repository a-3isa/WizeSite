import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/utils/number_parser.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CreateProjectScreen extends ConsumerStatefulWidget {
  const CreateProjectScreen({this.projectId, super.key});

  final String? projectId;

  @override
  ConsumerState<CreateProjectScreen> createState() =>
      _CreateProjectScreenState();
}

class _CreateProjectScreenState extends ConsumerState<CreateProjectScreen> {
  final _nameController = TextEditingController();
  final _clientController = TextEditingController();
  final _contractController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _budgetController = TextEditingController();
  double _completion = 0;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  String _status = 'active';
  bool _loading = false;
  bool _prefilling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.projectId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_prefill());
      });
    }
  }

  Future<void> _prefill() async {
    setState(() => _prefilling = true);
    try {
      final project = await ref
          .read(projectRepositoryProvider)
          .getProject(widget.projectId!);
      if (project != null && mounted) {
        setState(() {
          _nameController.text = project.name;
          _clientController.text = project.clientName;
          _contractController.text = project.contractValue.toStringAsFixed(2);
          _locationController.text = project.location;
          _descriptionController.text = project.description;
          if (project.budgetLimit != null) {
            _budgetController.text = project.budgetLimit!.toStringAsFixed(2);
          }
          if (project.startDate != null) _startDate = project.startDate!;
          _endDate = project.expectedEndDate;
          _completion = project.completionPercentage;
          _status = project.status;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).t('unexpectedErrorTryAgain');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _prefilling = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clientController.dispose();
    _contractController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    if (workspaceId == null || userId == null) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }

    final contract = NumberParser.parseDouble(_contractController.text);
    if (_nameController.text.trim().isEmpty ||
        contract == null ||
        contract < 0) {
      setState(() => _error = l10n.t('fillRequiredFields'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var queued = false;
      if (widget.projectId == null) {
        final result = await ref
            .read(projectRepositoryProvider)
            .createProject(
              workspaceId: workspaceId,
              userId: userId,
              name: _nameController.text.trim(),
              clientName: _clientController.text.trim(),
              contractValue: contract,
              startDate: _startDate,
              expectedEndDate: _endDate,
              location: _locationController.text.trim(),
              description: _descriptionController.text.trim(),
              budgetLimit: NumberParser.parseDouble(_budgetController.text),
              completionPercentage: _completion,
            );
        queued = result.queued;
      } else {
        await ref
            .read(projectRepositoryProvider)
            .updateProject(
              projectId: widget.projectId!,
              name: _nameController.text.trim(),
              clientName: _clientController.text.trim(),
              contractValue: contract,
              startDate: _startDate,
              expectedEndDate: _endDate,
              location: _locationController.text.trim(),
              description: _descriptionController.text.trim(),
              budgetLimit: NumberParser.parseDouble(_budgetController.text),
              completionPercentage: _completion,
              status: _status,
            );
      }
      if (mounted) {
        if (queued) {
          await ref.read(offlineQueueCoordinatorProvider).refreshCounts();
          unawaited(ref.read(offlineQueueCoordinatorProvider).drainNow());
          if (!mounted) {
            return;
          }
          pushAppUiNotice(ref, l10n.t('queuedForSync'));
        }
        context.go(
          widget.projectId == null
              ? AppRoutes.projects
              : AppRoutes.projectDetailPath(widget.projectId!),
        );
      }
    } on CallableClientException catch (e) {
      if (e.code == 'failed-precondition') {
        if (mounted) {
          context.push('${AppRoutes.subscriptionLimit}?limit=activeProjects');
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = appErrorMessage(l10n, e));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  InputDecoration _inputDecoration(String label, {bool required = false}) {
    return InputDecoration(
      labelText: required ? '$label *' : label,
      filled: true,
      fillColor: AppColors.surfaceSolid,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderGrey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderGrey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: AppColors.constructionOrange,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: isStart ? _startDate : (_endDate ?? DateTime.now()),
    );
    if (date == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      if (isStart) {
        _startDate = date;
      } else {
        _endDate = date;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fallbackRoute = widget.projectId == null
        ? AppRoutes.projects
        : AppRoutes.projectDetailPath(widget.projectId!);
    return AppBackScope(
      fallbackRoute: fallbackRoute,
      child: Scaffold(
        body: _prefilling
            ? const AppLoadingSkeleton(lineCount: 8)
            : SafeArea(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                        child: Row(
                          children: [
                            AppBackButton(fallbackRoute: fallbackRoute),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.projectId == null
                                    ? l10n.t('createProject')
                                    : l10n.t('editProjectTitle'),
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                      color: AppColors.textDark,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _SectionHeader(title: l10n.t('projectName')),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _nameController,
                            decoration: _inputDecoration(
                              l10n.t('projectName'),
                              required: true,
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _clientController,
                            decoration: _inputDecoration(l10n.t('clientName')),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _contractController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: _inputDecoration(
                              l10n.t('contractValue'),
                              required: true,
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 20),
                          _SectionHeader(title: l10n.t('location')),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _locationController,
                            decoration: _inputDecoration(l10n.t('location')),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descriptionController,
                            maxLines: 3,
                            decoration: _inputDecoration(l10n.t('description')),
                            textInputAction: TextInputAction.newline,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _budgetController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: _inputDecoration(l10n.t('budgetLimit')),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 20),
                          _SectionHeader(title: l10n.t('status')),
                          const SizedBox(height: 8),
                          BelowDropdownField<String>(
                            label: l10n.t('status'),
                            value: _status,
                            entries: [
                              DropdownMenuEntry(
                                value: 'active',
                                label: l10n.projectStatusLabel('active'),
                              ),
                              DropdownMenuEntry(
                                value: 'paused',
                                label: l10n.projectStatusLabel('paused'),
                              ),
                              DropdownMenuEntry(
                                value: 'completed',
                                label: l10n.projectStatusLabel('completed'),
                              ),
                              DropdownMenuEntry(
                                value: 'cancelled',
                                label: l10n.projectStatusLabel('cancelled'),
                              ),
                            ],
                            onSelected: (value) {
                              HapticFeedback.lightImpact();
                              setState(() => _status = value ?? 'active');
                            },
                          ),
                          const SizedBox(height: 20),
                          _SectionHeader(title: l10n.t('startDate')),
                          const SizedBox(height: 8),
                          _DateTile(
                            label: l10n.t(
                              'startDateWithValue',
                              params: {
                                'value': _startDate
                                    .toLocal()
                                    .toIso8601String()
                                    .split('T')
                                    .first,
                              },
                            ),
                            onTap: () => _pickDate(isStart: true),
                          ),
                          const SizedBox(height: 8),
                          _DateTile(
                            label: _endDate == null
                                ? l10n.t('expectedEndDateOptional')
                                : l10n.t(
                                    'expectedEndDateWithValue',
                                    params: {
                                      'value': _endDate!
                                          .toLocal()
                                          .toIso8601String()
                                          .split('T')
                                          .first,
                                    },
                                  ),
                            onTap: () => _pickDate(isStart: false),
                          ),
                          const SizedBox(height: 20),
                          _SectionHeader(title: l10n.t('completion')),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSolid,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.borderGrey),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      l10n.t(
                                        'completionLabel',
                                        params: {
                                          'value': '${_completion.toInt()}',
                                        },
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textDark,
                                          ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.constructionOrange
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${_completion.toInt()}%',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.constructionOrange,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor:
                                        AppColors.constructionOrange,
                                    thumbColor: AppColors.constructionOrange,
                                    overlayColor: AppColors.constructionOrange
                                        .withValues(alpha: 0.2),
                                  ),
                                  child: Slider(
                                    min: 0,
                                    max: 100,
                                    value: _completion,
                                    onChanged: (value) {
                                      HapticFeedback.selectionClick();
                                      setState(() => _completion = value);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.dangerLight,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.danger.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: AppColors.danger,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: AppColors.danger),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _loading ? null : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.constructionOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: _loading
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    widget.projectId == null
                                        ? l10n.t('saveProject')
                                        : l10n.t('updateProject'),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 32),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.textBody,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceSolid,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderGrey),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                color: AppColors.constructionOrange,
                size: 22,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textBody.withValues(alpha: 0.6),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
