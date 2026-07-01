import 'package:buildtrack_app/features/common/presentation/screens/domain_accounting_records_screen.dart';
import 'package:flutter/material.dart';

class TransportProvidersScreen extends StatelessWidget {
  const TransportProvidersScreen({
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
      titleKey: 'transportAccounting',
      collectionName: 'transport_provider_accounting_records',
      ownerIdField: 'providerId',
      ownerNameField: 'providerName',
      ownerId: providerId,
      ownerName: providerName,
      projectId: projectId,
    );
  }
}
