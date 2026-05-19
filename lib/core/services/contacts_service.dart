import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ContactPermissionStatus { granted, denied, blocked }

enum PickedContactStatus { selected, cancelled, missingPhoneNumber }

class PickedContact {
  const PickedContact({required this.name, required this.phoneNumber});

  final String name;
  final String phoneNumber;
}

class PickedContactResult {
  const PickedContactResult._({required this.status, this.contact});

  const PickedContactResult.selected(PickedContact contact)
    : this._(status: PickedContactStatus.selected, contact: contact);

  const PickedContactResult.cancelled()
    : this._(status: PickedContactStatus.cancelled);

  const PickedContactResult.missingPhoneNumber()
    : this._(status: PickedContactStatus.missingPhoneNumber);

  final PickedContactStatus status;
  final PickedContact? contact;
}

class ContactsService {
  const ContactsService();

  Future<ContactPermissionStatus> requestPermission() async {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    return _mapPermissionStatus(status.name);
  }

  Future<void> openSettings() {
    return FlutterContacts.permissions.openSettings();
  }

  Future<PickedContactResult> pickContact() async {
    final pickedId = await FlutterContacts.native.showPicker();
    if (pickedId == null || pickedId.trim().isEmpty) {
      return const PickedContactResult.cancelled();
    }
    final contact = await FlutterContacts.get(
      pickedId,
      properties: {ContactProperty.name, ContactProperty.phone},
    );
    final normalized = ContactsService.normalizePickedContact(
      fullName: contact?.displayName,
      phoneNumbers: contact?.phones.map((phone) => phone.number).toList() ?? const [],
    );
    if (normalized == null) {
      return const PickedContactResult.missingPhoneNumber();
    }
    return PickedContactResult.selected(normalized);
  }

  static PickedContact? normalizePickedContact({
    required String? fullName,
    required List<String?> phoneNumbers,
  }) {
    final phone = phoneNumbers
        .map((value) => (value ?? '').trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (phone.isEmpty) {
      return null;
    }
    final name = (fullName ?? '').trim();
    return PickedContact(name: name, phoneNumber: phone);
  }

  ContactPermissionStatus _mapPermissionStatus(String name) {
    switch (name) {
      case 'granted':
        return ContactPermissionStatus.granted;
      case 'denied':
        return ContactPermissionStatus.denied;
      default:
        return ContactPermissionStatus.blocked;
    }
  }
}

final contactsServiceProvider = Provider<ContactsService>((ref) {
  return const ContactsService();
});
