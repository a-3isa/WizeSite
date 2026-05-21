import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AddPaymentScreen extends ConsumerStatefulWidget {
  const AddPaymentScreen({this.paymentId, this.projectId, super.key});

  final String? paymentId;
  final String? projectId;

  @override
  ConsumerState<AddPaymentScreen> createState() => _AddPaymentScreenState();
}

class _AddPaymentScreenState extends ConsumerState<AddPaymentScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  String _method = 'cash';
  String? _projectId;
  DateTime _date = DateTime.now();
  bool _loading = false;
  bool _prefilling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.paymentId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_prefill());
      });
    } else if (widget.projectId != null) {
      _projectId = widget.projectId;
    }
  }

  Future<void> _prefill() async {
    setState(() => _prefilling = true);
    try {
      final payment = await ref
          .read(paymentRepositoryProvider)
          .getPayment(widget.paymentId!);
      if (payment != null && mounted) {
        setState(() {
          _projectId = payment.projectId;
          _amountController.text = payment.amount.toStringAsFixed(2);
          _method = payment.paymentMethod;
          _notesController.text = payment.notes;
          _date = payment.date;
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
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _fallbackRoute() {
    final projectId = _projectId ?? widget.projectId;
    if (projectId != null && projectId.isNotEmpty) {
      return AppRoutes.projectDetailPath(projectId);
    }
    return AppRoutes.payments;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    final userId = ref.read(activeUserIdProvider);
    final amount = double.tryParse(_amountController.text.trim());
    if (workspaceId == null || userId == null) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    if (_projectId == null || amount == null || amount <= 0) {
      setState(() => _error = l10n.t('selectProjectAndValidAmount'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var queued = false;
      if (widget.paymentId == null) {
        try {
          await ref
              .read(entitlementGuardProvider)
              .ensureCanCreate(
                workspaceId: workspaceId,
                type: LimitType.paymentsPerMonth,
              );
        } on LimitExceeded {
          if (mounted) {
            context.push(AppRoutes.subscriptionLimitPath('paymentsPerMonth'));
          }
          return;
        }
        if (kDebugMode) {
          debugPrint(
            '[add_payment.save] create start workspaceId=$workspaceId '
            'userId=$userId projectId=$_projectId amount=$amount '
            'method=$_method date=${_date.toIso8601String()}',
          );
        }
        final result = await ref
            .read(paymentRepositoryProvider)
            .createPayment(
              workspaceId: workspaceId,
              userId: userId,
              projectId: _projectId!,
              amount: amount,
              date: _date,
              paymentMethod: _method,
              notes: _notesController.text.trim(),
            );
        queued = result.queued;
        if (kDebugMode) {
          debugPrint(
            '[add_payment.save] create result queued=${result.queued} '
            'id=${result.id}',
          );
        }
      } else {
        await ref
            .read(paymentRepositoryProvider)
            .updatePayment(
              paymentId: widget.paymentId!,
              amount: amount,
              date: _date,
              paymentMethod: _method,
              notes: _notesController.text.trim(),
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
        appNavigateBack(context, fallbackRoute: _fallbackRoute());
      }
    } on CallableClientException catch (e) {
      if (e.code == 'failed-precondition') {
        if (mounted) {
          context.push('${AppRoutes.subscriptionLimit}?limit=paymentsPerMonth');
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.t('unexpectedErrorTryAgain'));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(projectsProvider);
    return AppBackScope(
      fallbackRoute: _fallbackRoute(),
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: widget.paymentId == null
              ? l10n.t('addPaymentTitle')
              : l10n.t('editPaymentTitle'),
          fallbackRoute: _fallbackRoute(),
        ),
        body: _prefilling
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  projectsAsync.when(
                    data: (projects) => BelowDropdownField<String>(
                      label: l10n.t('project'),
                      value: _projectId,
                      entries: projects
                          .map(
                            (p) =>
                                DropdownMenuEntry(value: p.id, label: p.name),
                          )
                          .toList(),
                      onSelected: (value) => setState(() => _projectId = value),
                    ),
                    error: (e, _) => Text(e.toString()),
                    loading: () => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l10n.t('amount')),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      l10n.t(
                        'dateWithValue',
                        params: {
                          'value': _date.toIso8601String().split('T').first,
                        },
                      ),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: _date,
                      );
                      if (picked != null) {
                        setState(() => _date = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  BelowDropdownField<String>(
                    label: l10n.t('paymentMethod'),
                    value: _method,
                    entries: [
                      DropdownMenuEntry(
                        value: 'cash',
                        label: l10n.paymentMethodLabel('cash'),
                      ),
                      DropdownMenuEntry(
                        value: 'bank',
                        label: l10n.paymentMethodLabel('bank'),
                      ),
                      DropdownMenuEntry(
                        value: 'check',
                        label: l10n.paymentMethodLabel('check'),
                      ),
                    ],
                    onSelected: (value) =>
                        setState(() => _method = value ?? 'cash'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: l10n.t('notes')),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.paymentId == null
                                ? l10n.t('savePayment')
                                : l10n.t('updatePayment'),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
