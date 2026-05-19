# Worker Selection And Contacts Design

Date: 2026-05-18

## Goal

Fix the worker selection crash in the worker-entry flow and add a contact picker on the worker form that imports both the contact name and phone number.

## Problem

The current `AddWorkerEntryScreen` assumes the selected `workerId` is always present in the current `workersProvider` list. That is fragile after worker creation, navigation races, or stale route parameters. When the selected ID is missing from the dropdown items, the worker picker becomes unstable and the screen can fail.

The worker form also requires manual entry for name and phone number even when the worker already exists in the device contacts.

## Approach

### 1. Stabilize worker selection in `AddWorkerEntryScreen`

- Always resolve the worker dropdown against the current worker list instead of assuming `_workerId` is valid.
- If `_workerId` is set but not present in the fetched worker list:
  - clear the invalid selection
  - show the normal worker picker
  - keep the rest of the form usable
- If the route was opened with a concrete worker ID and that ID is still valid, preserve it.

This keeps the UI deterministic and avoids dropdown/value mismatch failures.

### 2. Add contact import on `AddWorkerScreen`

- Add a “Pick from Contacts” action near the worker name and phone fields.
- On tap:
  - request contacts permission
  - open a native contact picker
  - extract the chosen contact’s display name and first non-empty phone number
  - fill both `_nameController` and `_phoneController`
- If the contact has no usable number:
  - show a friendly message
  - leave existing form values unchanged
- If permission is denied or picker is cancelled:
  - do not fail the form
  - keep the current values intact

## Architecture

### New service

Add a small contacts abstraction in `lib/core/services/contacts_service.dart`:

- `ContactsService`
- `ContactPermissionStatus`
- `PickedContact`

Responsibilities:
- check/request contacts permission
- open the picker
- normalize the chosen name and phone number

This keeps plugin details out of `AddWorkerScreen` and makes widget tests straightforward.

### UI changes

`AddWorkerScreen`
- add a secondary button or list tile for contact import
- use `ContactsService` to fetch data
- fill name and phone controllers from the picked contact

`AddWorkerEntryScreen`
- validate the current `_workerId` against fetched workers before building the dropdown
- avoid passing an invalid `initialValue`/selected value into the picker

## Error Handling

- Missing worker in entry form: recover by clearing the invalid selection instead of throwing.
- Contacts permission denied: show a non-blocking error.
- Contact has no phone number: show a non-blocking error.
- Picker cancelled: no state change, no error.

## Testing

Add failing tests first for:

1. `AddWorkerEntryScreen`
- survives when route/default `_workerId` is not present in the worker list
- lets the user choose a valid worker afterward

2. `AddWorkerScreen`
- fills both name and phone from a picked contact
- handles permission denied without overwriting fields
- handles contact-without-phone without overwriting fields

## Scope Limits

- No bulk contact import
- No worker sync back into device contacts
- No silent contact access; user must explicitly pick a contact
