import 'package:buildtrack_app/features/transport/data/transport_provider_accounting_repository.dart';
import 'package:buildtrack_app/features/transport/domain/transport_provider_accounting_record.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'transport provider accounting records persist and list by provider',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repository = TransportProviderAccountingRepository(firestore);
      await repository.save(
        TransportProviderAccountingRecord(
          id: 'record_1',
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          providerId: 'transport_1',
          providerName: 'Truck Fleet',
          description: 'Material delivery',
          amount: 180,
          date: DateTime.utc(2026, 5, 20),
          paymentMethod: 'cash',
          paymentStatus: 'paid',
          attachments: const [],
        ),
      );

      final records = await repository.fetchForProvider(
        workspaceId: 'workspace_1',
        providerId: 'transport_1',
      );
      expect(records.single.providerName, 'Truck Fleet');
      expect(records.single.paymentStatus, 'paid');
    },
  );
}
