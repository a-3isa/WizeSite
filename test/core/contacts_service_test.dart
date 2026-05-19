import 'package:buildtrack_app/core/services/contacts_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizePickedContact keeps name and first non-empty phone number', () {
    final result = ContactsService.normalizePickedContact(
      fullName: 'Ali Hassan',
      phoneNumbers: const ['   ', '+20 100 555 0101'],
    );

    expect(result, isNotNull);
    expect(result!.name, 'Ali Hassan');
    expect(result.phoneNumber, '+20 100 555 0101');
  });

  test('normalizePickedContact returns null when no phone number exists', () {
    final result = ContactsService.normalizePickedContact(
      fullName: 'Ali Hassan',
      phoneNumbers: const [' ', ''],
    );

    expect(result, isNull);
  });
}
