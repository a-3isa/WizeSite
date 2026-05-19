import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/contacts_service.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/add_worker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeContactsService extends ContactsService {
  const _FakeContactsService({
    required this.permissionStatus,
    required this.pickResult,
  });

  final ContactPermissionStatus permissionStatus;
  final PickedContactResult pickResult;

  @override
  Future<PickedContactResult> pickContact() async => pickResult;

  @override
  Future<ContactPermissionStatus> requestPermission() async => permissionStatus;
}

Widget _testApp(ContactsService contactsService) {
  return ProviderScope(
    overrides: [
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
      activeUserIdProvider.overrideWith((ref) => 'user_1'),
      contactsServiceProvider.overrideWithValue(contactsService),
    ],
    child: const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: AddWorkerScreen(),
    ),
  );
}

void main() {
  testWidgets('AddWorkerScreen imports name and phone from contacts', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const _FakeContactsService(
          permissionStatus: ContactPermissionStatus.granted,
          pickResult: PickedContactResult.selected(
            PickedContact(name: 'Ali Hassan', phoneNumber: '+201005550101'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick from Contacts'));
    await tester.pumpAndSettle();

    expect(find.text('Ali Hassan'), findsOneWidget);
    expect(find.text('+201005550101'), findsOneWidget);
  });

  testWidgets(
    'AddWorkerScreen keeps fields untouched when contacts permission is denied',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          const _FakeContactsService(
            permissionStatus: ContactPermissionStatus.denied,
            pickResult: PickedContactResult.cancelled(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Manual Worker');
      await tester.enterText(find.byType(TextField).at(1), '0100');
      await tester.tap(find.text('Pick from Contacts'));
      await tester.pumpAndSettle();

      expect(find.text('Manual Worker'), findsOneWidget);
      expect(find.text('0100'), findsOneWidget);
      expect(
        find.text(
          'Contacts access is needed to import a worker name and phone number.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'AddWorkerScreen keeps fields untouched when selected contact has no phone',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          const _FakeContactsService(
            permissionStatus: ContactPermissionStatus.granted,
            pickResult: PickedContactResult.missingPhoneNumber(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Manual Worker');
      await tester.enterText(find.byType(TextField).at(1), '0100');
      await tester.tap(find.text('Pick from Contacts'));
      await tester.pumpAndSettle();

      expect(find.text('Manual Worker'), findsOneWidget);
      expect(find.text('0100'), findsOneWidget);
      expect(
        find.text('The selected contact does not have a phone number.'),
        findsOneWidget,
      );
    },
  );
}
