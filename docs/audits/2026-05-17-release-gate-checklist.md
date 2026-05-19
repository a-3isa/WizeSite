# Release Gate Checklist

## Repo Verification

- Run `flutter test`
- Run `flutter analyze`
- Run `dart run tool/release_audit.dart`
- Run `cd functions && npm test`
- Run emulator-backed backend verification:
  - `firebase emulators:exec --config ..\firebase.json --only firestore "npm run build && node --test lib/firestore_rules.test.js lib/project_recompute_trigger.test.js"`

## Required Firebase Console Checks

### Android / Google Sign-In

- Confirm `com.ahmed.buildozer` exists as the active Android app in Firebase.
- Add Android OAuth clients for `com.ahmed.buildozer` with:
  - debug SHA-1 / SHA-256
  - release or upload SHA-1 / SHA-256
- Regenerate `android/app/google-services.json`.
- Verify the regenerated `com.ahmed.buildozer` client includes an Android OAuth client (`client_type: 1`).

### App Check

- Confirm App Check is configured for:
  - Android Play Integrity
  - Apple App Attest / DeviceCheck fallback
- Confirm local debug tokens are allowlisted where needed for dev smoke tests.

### RevenueCat

- Confirm webhook secret `REVENUECAT_WEBHOOK_SECRET` is set in Firebase Functions secrets.
- Confirm RevenueCat entitlement ID matches client expectation: `wizesite_pro`.
- Confirm default offering/paywall is published.

## Platform Config Diff Checks

### Android

- `android.permission.INTERNET` present
- `android.permission.RECORD_AUDIO` present
- `android.permission.READ_CONTACTS` present
- package name aligned with Firebase and Codemagic: `com.ahmed.buildozer`
- signed build uses the same package and expected upload key

### iOS

- `NSMicrophoneUsageDescription` present
- `NSPhotoLibraryUsageDescription` present
- `NSCameraUsageDescription` present
- `NSContactsUsageDescription` present
- URL scheme in `Info.plist` matches `GoogleService-Info.plist`

## Smoke Paths

### Auth

- Email/password login
- Google Sign-In on Android debug build
- Google Sign-In on Android signed/internal build
- Session restore after app restart
- Logout then login again

### Data / Sync

- Create expense/payment/worker entry offline
- Reconnect and verify queue drains
- Confirm dashboard and reports reflect synced results
- Confirm dead-letter notice is meaningful for invalid queued actions

### Voice Expense

- Record audio
- Upload successfully
- Parse transcript
- Review/edit fields
- Save confirmed expense

### Subscription

- Hit a free-plan quota limit
- Open paywall
- Purchase or restore on supported platform
- Verify quota-restricted action becomes available

## Release Decision

- `READY` if all repo checks pass, emulator suites pass, no open `P0`, and all `P1` items are fixed or explicitly waived.
- `READY WITH NON-BLOCKERS` if only `P2/P3` items remain.
- `NOT READY` if Android OAuth/App Check/critical auth/sync/subscription flows are unresolved.
