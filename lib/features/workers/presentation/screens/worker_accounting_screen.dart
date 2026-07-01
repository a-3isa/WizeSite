import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/features/common/presentation/controllers/domain_accounting_record_draft.dart';
import 'package:buildtrack_app/features/common/presentation/screens/domain_accounting_records_screen.dart';
import 'package:buildtrack_app/features/workers/data/worker_accounting_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_accounting_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkerAccountingScreen extends StatelessWidget {
  const WorkerAccountingScreen({
    required this.workerId,
    required this.workerName,
    this.projectId,
    super.key,
  });

  final String workerId;
  final String workerName;
  final String? projectId;

  @override
  Widget build(BuildContext context) {
    return DomainAccountingRecordsScreen(
      titleKey: 'workerAccounting',
      collectionName: 'worker_accounting_records',
      ownerIdField: 'workerId',
      ownerNameField: 'workerName',
      ownerId: workerId,
      ownerName: workerName,
      projectId: projectId,
      showPaidAmountField: true,
      headerBuilder: (context, ref, workspaceId) =>
          _WorkerSummaryHeader(workspaceId: workspaceId, workerId: workerId),
      onSave: (draft) async {
        final validationKey = WorkerAccountingRecord.validatePaidAmount(
          paymentStatus: draft.paymentStatus,
          amount: draft.amount,
          paidAmount: draft.paidAmount,
        );
        if (validationKey != null) {
          throw DomainAccountingValidationException(validationKey);
        }
        final repository = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(workerAccountingRepositoryProvider);
        await repository.save(
          WorkerAccountingRecord(
            id: '',
            workspaceId: draft.workspaceId,
            projectId: draft.projectId,
            workerId: draft.ownerId,
            workerName: draft.ownerName,
            description: draft.description,
            amount: draft.amount,
            date: draft.date,
            paymentMethod: draft.paymentMethod,
            paymentStatus: draft.paymentStatus,
            paidAmount: draft.paymentStatus == 'partial'
                ? draft.paidAmount
                : null,
            notes: draft.notes,
          ),
        );
      },
    );
  }
}

class _WorkerSummaryHeader extends ConsumerWidget {
  const _WorkerSummaryHeader({
    required this.workspaceId,
    required this.workerId,
  });

  final String workspaceId;
  final String workerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return FutureBuilder<WorkerAccountingSummary?>(
      future: ref
          .read(workerAccountingRepositoryProvider)
          .fetchSummary(workspaceId: workspaceId, workerId: workerId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppLoadingSkeleton(lineCount: 2);
        }
        final summary = snapshot.data;
        if (summary == null) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text(l10n.t('workerConfirmedPaid')),
                    trailing: Text(
                      Formatters.money(summary.confirmedPaid, locale: locale),
                    ),
                  ),
                  ListTile(
                    title: Text(l10n.t('workerConfirmedOutstanding')),
                    trailing: Text(
                      Formatters.money(
                        summary.confirmedOutstanding,
                        locale: locale,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (summary.hasUnresolvedLegacy)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppRecoverableError(
                  message: l10n.t('workerLegacyPartialUnresolved'),
                ),
              ),
          ],
        );
      },
    );
  }
}
