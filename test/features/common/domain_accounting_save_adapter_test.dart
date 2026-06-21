import 'package:buildtrack_app/features/common/presentation/controllers/domain_accounting_record_draft.dart';
import 'package:buildtrack_app/features/common/presentation/controllers/domain_accounting_save_adapter.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'saves generic domain accounting records without worker-only fields',
    () async {
      final firestore = FakeFirebaseFirestore();
      final adapter = DomainAccountingSaveAdapter(firestore);
      final date = DateTime.utc(2026, 6, 17);

      await adapter.save(
        collectionName: 'contractor_accounting_records',
        draft: DomainAccountingRecordDraft(
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          ownerIdField: 'contractorId',
          ownerNameField: 'contractorName',
          ownerId: 'contractor_1',
          ownerName: 'Acme Concrete',
          description: 'Concrete pour',
          amount: 1200,
          date: date,
          paymentMethod: 'cash',
          paymentStatus: 'partial',
          paidAmount: 500,
          notes: 'North slab',
        ),
      );

      final saved = await firestore
          .collection('contractor_accounting_records')
          .get();
      expect(saved.docs, hasLength(1));

      final data = saved.docs.single.data();
      expect(data['workspaceId'], 'workspace_1');
      expect(data['projectId'], 'project_1');
      expect(data['contractorId'], 'contractor_1');
      expect(data['contractorName'], 'Acme Concrete');
      expect(data['description'], 'Concrete pour');
      expect(data['amount'], 1200);
      expect(data['paymentMethod'], 'cash');
      expect(data['paymentStatus'], 'partial');
      expect(data['notes'], 'North slab');
      expect(data['attachments'], isEmpty);
      expect(data, isNot(contains('paidAmount')));
    },
  );
}
