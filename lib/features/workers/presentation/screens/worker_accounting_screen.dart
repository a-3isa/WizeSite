import 'package:buildtrack_app/features/common/presentation/screens/domain_accounting_records_screen.dart';
import 'package:flutter/material.dart';

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
    );
  }
}
