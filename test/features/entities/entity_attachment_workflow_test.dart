import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/widgets/attachment_tile.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entity records preserve attachment metadata only', () {
    final entity = AppEntity.fromMap('entity_1', {
      'workspaceId': 'workspace_1',
      'name': 'Supplier One',
      'normalizedName': 'supplier one',
      'type': 'supplier',
      'createdAt': DateTime.utc(2026, 5, 1).toIso8601String(),
      'attachments': [
        {
          'id': 'attachment_1',
          'fileName': 'receipt.pdf',
          'storagePath': 'entities/entity_1/receipt.pdf',
          'downloadUrl': 'https://example.com/receipt.pdf',
          'contentType': 'application/pdf',
          'size': 4096,
          'uploadedAt': DateTime.utc(2026, 5, 2).toIso8601String(),
        },
      ],
    });

    expect(entity.attachments, hasLength(1));
    expect(entity.attachments.single.fileName, 'receipt.pdf');
    expect(entity.toMap()['attachments'], isA<List<Object?>>());
    expect('${entity.toMap()}', isNot(contains('base64')));
  });

  testWidgets(
    'entity attachment preview/open is blocked for unauthorized roles',
    (tester) async {
      var opened = false;
      final attachment = Attachment(
        id: 'attachment_1',
        fileName: 'receipt.pdf',
        storagePath: 'entities/entity_1/receipt.pdf',
        downloadUrl: 'https://example.com/receipt.pdf',
        contentType: 'application/pdf',
        uploadedAt: DateTime.utc(2026, 5, 2),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttachmentTile(
              attachment: attachment,
              canAccess: false,
              deniedMessage: 'Only accounting users can open attachments.',
              onOpen: () => opened = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.open_in_new));
      await tester.pump();

      expect(opened, isFalse);
      expect(
        find.text('Only accounting users can open attachments.'),
        findsOneWidget,
      );
    },
  );
}
