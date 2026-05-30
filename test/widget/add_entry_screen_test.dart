import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/add/presentation/screens/add_entry_screen.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:buildtrack_app/core/services/attachment_validation_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker();

  FilePickerResult? nextResult;
  FileType? lastType;
  List<String>? lastAllowedExtensions;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    lastType = type;
    lastAllowedExtensions = allowedExtensions;
    return nextResult;
  }
}

void main() {
  testWidgets('AddEntryScreen exposes quick expense structured fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
          projectsProvider.overrideWith((ref) => Stream.value(const [])),
          workersProvider.overrideWith((ref) => Stream.value(const [])),
          currentUserSettingsProvider.overrideWith(
            (ref) => Stream.value(
              UserSettings.defaults(userId: 'user_1', email: 'user@test.com'),
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: AddEntryScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Purpose'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Payment method'), findsOneWidget);
    expect(find.text('Payment status'), findsOneWidget);
  });

  testWidgets('AddEntryScreen validates attachments before upload', (
    tester,
  ) async {
    final fakePicker = _FakeFilePicker();
    FilePicker? originalPicker;
    try {
      originalPicker = FilePicker.platform;
    } catch (_) {
      originalPicker = null;
    }
    FilePicker.platform = fakePicker;
    addTearDown(() {
      if (originalPicker != null) {
        FilePicker.platform = originalPicker;
      }
    });

    fakePicker.nextResult = FilePickerResult([
      PlatformFile(name: 'receipt.pdf', path: '/tmp/receipt.pdf', size: 1024),
      PlatformFile(name: 'malware.exe', path: '/tmp/malware.exe', size: 1024),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
          projectsProvider.overrideWith((ref) => Stream.value(const [])),
          workersProvider.overrideWith((ref) => Stream.value(const [])),
          currentUserSettingsProvider.overrideWith(
            (ref) => Stream.value(
              UserSettings.defaults(userId: 'user_1', email: 'user@test.com'),
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: AddEntryScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(AddEntryScreen), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);

    final attachmentTextFinder = find.text('Select attachments');

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(attachmentTextFinder, findsOneWidget);
    await tester.tap(attachmentTextFinder);
    await tester.pumpAndSettle();

    expect(fakePicker.lastType, FileType.custom);
    expect(
      fakePicker.lastAllowedExtensions,
      AttachmentValidationService.allowedExtensionsForPicker,
    );
    expect(find.textContaining('Unsupported attachment type'), findsOneWidget);
    expect(find.text('receipt.pdf'), findsOneWidget);
    expect(find.text('malware.exe'), findsNothing);
  });
}
