import 'package:buildtrack_app/features/contractors/data/contractor_accounting_repository.dart';
import 'package:buildtrack_app/features/contractors/domain/contractor_accounting_record.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contractor accounting records persist and list by contractor', () async {
    final firestore = FakeFirebaseFirestore();
    final repository = ContractorAccountingRepository(firestore);
    await repository.save(
      ContractorAccountingRecord(
        id: 'record_1',
        workspaceId: 'workspace_1',
        projectId: 'project_1',
        contractorId: 'contractor_1',
        contractorName: 'Concrete Crew',
        description: 'Foundation pour',
        amount: 900,
        date: DateTime.utc(2026, 5, 20),
        paymentMethod: 'bank',
        paymentStatus: 'partial',
        attachments: const [],
      ),
    );

    final records = await repository.fetchForContractor(
      workspaceId: 'workspace_1',
      contractorId: 'contractor_1',
    );
    expect(records.single.contractorName, 'Concrete Crew');
    expect(records.single.paymentStatus, 'partial');
  });
}
