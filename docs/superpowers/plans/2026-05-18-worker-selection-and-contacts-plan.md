# Worker Selection And Contacts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix worker-entry selection crashes and let users import a worker's name and phone number from device contacts.

**Architecture:** Keep the worker-entry fix inside `AddWorkerEntryScreen` by reconciling the selected worker ID against the live worker list before building the dropdown. Add a small `ContactsService` abstraction so `AddWorkerScreen` can request contact permission, pick a contact, and fill the form without binding UI code directly to a platform plugin.

**Tech Stack:** Flutter, Riverpod, widget tests, `permission_handler`, one contact picker package, platform manifests/plists.

---

### Task 1: Add failing worker-entry regression test

**Files:**
- Create: `test/widget/add_worker_entry_screen_test.dart`
- Modify: `lib/features/workers/presentation/screens/add_worker_entry_screen.dart`
- Test: `test/widget/add_worker_entry_screen_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
testWidgets(
  'AddWorkerEntryScreen clears an invalid selected worker and lets the user pick a valid one',
  (tester) async {
    // Start screen with widget.workerId = 'worker_missing'
    // Provide workersProvider with only worker_1 and worker_2
    // Verify the screen renders instead of failing
    // Choose worker_1 from dropdown
    // Expect no error and worker_1 remains selected
  },
);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/add_worker_entry_screen_test.dart`
Expected: FAIL because the current screen still passes an invalid selected worker state into the dropdown flow.

- [ ] **Step 3: Write minimal implementation**

```dart
String? _resolvedWorkerValue(List<WorkerProfile> workers) {
  final current = _workerId;
  if (current == null || current.isEmpty || current == 'new') {
    return null;
  }
  final exists = workers.any((worker) => worker.id == current);
  if (exists) {
    return current;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _workerId == current) {
      setState(() => _workerId = null);
    }
  });
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/add_worker_entry_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add test/widget/add_worker_entry_screen_test.dart lib/features/workers/presentation/screens/add_worker_entry_screen.dart
git commit -m "fix: stabilize worker entry selection"
```

### Task 2: Add contacts service test coverage

**Files:**
- Create: `test/core/contacts_service_test.dart`
- Create: `lib/core/services/contacts_service.dart`
- Modify: `pubspec.yaml`
- Test: `test/core/contacts_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/contacts_service_test.dart`
Expected: FAIL because `ContactsService` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```dart
enum ContactPermissionStatus { granted, denied, blocked }

class PickedContact {
  const PickedContact({required this.name, required this.phoneNumber});

  final String name;
  final String phoneNumber;
}

class ContactsService {
  static PickedContact? normalizePickedContact({
    required String? fullName,
    required List<String?> phoneNumbers,
  }) {
    final name = (fullName ?? '').trim();
    final phone = phoneNumbers
        .map((value) => (value ?? '').trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (phone.isEmpty) {
      return null;
    }
    return PickedContact(name: name, phoneNumber: phone);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/contacts_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add test/core/contacts_service_test.dart lib/core/services/contacts_service.dart pubspec.yaml
git commit -m "feat: add contacts service abstraction"
```

### Task 3: Add failing worker form contact-import widget tests

**Files:**
- Create: `test/widget/add_worker_screen_test.dart`
- Modify: `lib/features/workers/presentation/screens/add_worker_screen.dart`
- Test: `test/widget/add_worker_screen_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('AddWorkerScreen imports name and phone from contacts', (tester) async {
  // Fake ContactsService returns granted + PickedContact('Ali Hassan', '+201005550101')
  // Tap contact import action
  // Expect both text fields populated
});

testWidgets('AddWorkerScreen keeps fields untouched when contact has no phone', (tester) async {
  // Fake ContactsService returns granted + null picked contact result
  // Expect error message and unchanged fields
});

testWidgets('AddWorkerScreen keeps fields untouched when contacts permission is denied', (tester) async {
  // Fake ContactsService returns denied
  // Expect non-blocking error and unchanged fields
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/add_worker_screen_test.dart`
Expected: FAIL because no contact import action or `ContactsService` integration exists yet.

- [ ] **Step 3: Write minimal implementation**

```dart
Future<void> _importFromContacts() async {
  final l10n = AppLocalizations.of(context);
  final contacts = ref.read(contactsServiceProvider);
  final status = await contacts.requestPermission();
  if (status != ContactPermissionStatus.granted) {
    setState(() => _error = l10n.t('contactsPermissionDenied'));
    return;
  }
  final contact = await contacts.pickContact();
  if (contact == null) {
    return;
  }
  setState(() {
    _nameController.text = contact.name;
    _phoneController.text = contact.phoneNumber;
    _error = null;
  });
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/add_worker_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add test/widget/add_worker_screen_test.dart lib/features/workers/presentation/screens/add_worker_screen.dart
git commit -m "feat: import worker contacts into form"
```

### Task 4: Hook up platform permission/config for contacts

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Modify: `docs/audits/2026-05-17-release-gate-checklist.md`
- Modify: `tool/release_audit.dart`
- Test: `dart run tool/release_audit.dart`

- [ ] **Step 1: Write the failing release audit expectation**

```dart
// Add checks for READ_CONTACTS in AndroidManifest and NSContactsUsageDescription in Info.plist
```

- [ ] **Step 2: Run audit to verify it fails**

Run: `dart run tool/release_audit.dart`
Expected: FAIL because contacts permissions are not yet declared.

- [ ] **Step 3: Write minimal implementation**

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.READ_CONTACTS" />
```

```xml
<!-- Info.plist -->
<key>NSContactsUsageDescription</key>
<string>Buildozer uses your contacts so you can import a worker's name and phone number into the worker form.</string>
```

- [ ] **Step 4: Run audit to verify it passes these checks**

Run: `dart run tool/release_audit.dart`
Expected: PASS for contacts permission checks. Any Firebase OAuth failure unrelated to this task can remain if still external.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist docs/audits/2026-05-17-release-gate-checklist.md tool/release_audit.dart
git commit -m "chore: add contacts permission release checks"
```

### Task 5: Run final verification

**Files:**
- Verify only

- [ ] **Step 1: Run focused tests**

Run:
```bash
flutter test test/core/contacts_service_test.dart
flutter test test/widget/add_worker_screen_test.dart
flutter test test/widget/add_worker_entry_screen_test.dart
```

Expected: PASS

- [ ] **Step 2: Run broad verification**

Run:
```bash
flutter analyze
flutter test
dart run tool/release_audit.dart
```

Expected:
- `flutter analyze`: PASS
- `flutter test`: PASS
- `dart run tool/release_audit.dart`: PASS for repo-side checks, with any remaining external Firebase OAuth issue reported separately if still applicable

- [ ] **Step 3: Commit**

```bash
git add .
git commit -m "feat: harden worker flows and import contacts"
```
