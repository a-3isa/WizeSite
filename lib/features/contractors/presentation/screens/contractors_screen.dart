import 'package:buildtrack_app/features/common/presentation/screens/domain_accounting_records_screen.dart';
import 'package:flutter/material.dart';

class ContractorsScreen extends StatelessWidget {
  const ContractorsScreen({
    required this.contractorId,
    required this.contractorName,
    this.projectId,
    super.key,
  });

  final String contractorId;
  final String contractorName;
  final String? projectId;

  @override
  Widget build(BuildContext context) {
    return DomainAccountingRecordsScreen(
      titleKey: 'contractorAccounting',
      collectionName: 'contractor_accounting_records',
      ownerIdField: 'contractorId',
      ownerNameField: 'contractorName',
      ownerId: contractorId,
      ownerName: contractorName,
      projectId: projectId,
    );
  }
}
