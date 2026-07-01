import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/widgets/attachment_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Attachment attachment({
    String contentType = 'application/pdf',
    String? downloadUrl = 'https://example.com/receipt.pdf',
    AttachmentUploadStatus uploadStatus = AttachmentUploadStatus.uploaded,
  }) {
    return Attachment(
      id: 'attachment_1',
      fileName: contentType.startsWith('image/')
          ? 'receipt.png'
          : 'receipt.pdf',
      storagePath: 'attachments/receipt',
      downloadUrl: downloadUrl,
      contentType: contentType,
      size: 2048,
      uploadedAt: DateTime.utc(2026, 5, 27),
      uploadStatus: uploadStatus,
    );
  }

  Future<void> pumpTile(WidgetTester tester, Widget child) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  testWidgets('denies open/download when accounting access is missing', (
    tester,
  ) async {
    var opened = false;

    await pumpTile(
      tester,
      AttachmentTile(
        attachment: attachment(),
        canAccess: false,
        deniedMessage: 'Access denied for attachments.',
        onOpen: () => opened = true,
      ),
    );

    await tester.tap(find.byIcon(Icons.open_in_new));
    await tester.pump();

    expect(opened, isFalse);
    expect(find.text('Access denied for attachments.'), findsOneWidget);
  });

  testWidgets('shows missing-file error instead of opening attachment', (
    tester,
  ) async {
    var opened = false;

    await pumpTile(
      tester,
      AttachmentTile(
        attachment: attachment(
          downloadUrl: '',
          uploadStatus: AttachmentUploadStatus.missingLocalFile,
        ),
        onOpen: () => opened = true,
      ),
    );

    await tester.tap(find.byIcon(Icons.open_in_new));
    await tester.pump();

    expect(opened, isFalse);
    expect(find.text('Attachment file is missing.'), findsOneWidget);
  });

  testWidgets('opens image attachments in a zoomable preview dialog', (
    tester,
  ) async {
    await pumpTile(
      tester,
      AttachmentTile(
        attachment: attachment(
          contentType: 'image/png',
          downloadUrl: 'https://example.com/receipt.png',
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.zoom_in));
    await tester.pumpAndSettle();

    expect(find.text('receipt.png'), findsWidgets);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byIcon(Icons.download), findsOneWidget);
  });
}
