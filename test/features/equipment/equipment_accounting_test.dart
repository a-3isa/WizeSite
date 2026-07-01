import 'package:buildtrack_app/features/equipment/data/equipment_accounting_repository.dart';
import 'package:buildtrack_app/features/equipment/domain/equipment_accounting_record.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('equipment accounting records persist and list by provider', () async {
    final firestore = FakeFirebaseFirestore();
    final repository = EquipmentAccountingRepository(firestore);
    await repository.save(
      EquipmentAccountingRecord(
        id: 'record_1',
        workspaceId: 'workspace_1',
        projectId: 'project_1',
        providerId: 'provider_1',
        providerName: 'Crane Rental',
        description: 'Crane day rental',
        amount: 600,
        date: DateTime.utc(2026, 5, 20),
        paymentMethod: 'cash',
        paymentStatus: 'unpaid',
        attachments: const [],
      ),
    );

    final records = await repository.fetchForProvider(
      workspaceId: 'workspace_1',
      providerId: 'provider_1',
    );
    expect(records.single.providerName, 'Crane Rental');
    expect(records.single.amount, 600);
  });
}
