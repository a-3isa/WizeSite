import 'package:buildtrack_app/features/common/presentation/screens/domain_accounting_records_screen.dart';
import 'package:flutter/material.dart';

class EquipmentScreen extends StatelessWidget {
  const EquipmentScreen({
    required this.providerId,
    required this.providerName,
    this.projectId,
    super.key,
  });

  final String providerId;
  final String providerName;
  final String? projectId;

  @override
  Widget build(BuildContext context) {
    return DomainAccountingRecordsScreen(
      titleKey: 'equipmentAccounting',
      collectionName: 'equipment_accounting_records',
      ownerIdField: 'providerId',
      ownerNameField: 'providerName',
      ownerId: providerId,
      ownerName: providerName,
      projectId: projectId,
    );
  }
}
