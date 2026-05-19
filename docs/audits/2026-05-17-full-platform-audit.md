# Full-Platform Reliability Audit

Date: 2026-05-17  
Scope: Flutter client, Firebase Functions, Firestore/Storage rules, Android/iOS runtime config, subscriptions, voice expense pipeline, reports, sync, and release readiness.

## Baseline

- `flutter test`: passing at audit start
- `functions npm test`: passing at audit start
- Emulator-backed rules/recompute suites exist and are part of backend release verification

## Audit Matrix

| Subsystem | Source of Truth | Automated Coverage | Manual Verification Path | High-Risk Seams | Status |
| --- | --- | --- | --- | --- | --- |
| Data sync & consistency | `lib/core/services/offline_action_queue.dart`, `lib/core/services/offline_queue_coordinator.dart`, `lib/core/services/workspace_mutation_service.dart`, `functions/src/index.ts`, `lib/features/reports/data/reports_providers.dart` | queue tests, report provider tests, recompute trigger tests | create/archive project finance records offline, reconnect, verify reports and metrics | error-code loss inside queued replay, dead-letter visibility, fallback metrics | Hardened in this pass |
| Security rules + Cloud Functions | `firestore.rules`, `storage.rules`, `functions/src/index.ts` | Firestore rules suite, recompute trigger suite | run emulator rules + trigger suites | cross-workspace isolation, archive semantics, bootstrap edge cases, App Check | Partially hardened, emulator verification required |
| Subscriptions / RevenueCat / quotas | `lib/features/subscription/`, `functions/src/index.ts`, `REVENUECAT_SETUP.md` | entitlement tests, usage tests, cap-hit integration tests | inspect RevenueCat dashboard + paywall, restore flow, quota hit flow | dashboard entitlement alignment, webhook secret/config drift | Repo stable, console verification required |
| Voice expense pipeline | `lib/features/voice_expense/`, `functions/src/voice/`, `lib/core/services/voice_recorder_service.dart` | parser tests, recorder test | record, upload, parse, review, save | upload/process/save timing, voice save failures, project resolution | Telemetry added |
| Auth flows | `lib/features/auth/`, `lib/core/services/session_restore_service.dart`, `lib/app/router.dart` | router redirect tests, splash restore tests, onboarding test, session restore service tests | email login, Google login, splash restore, logout/login transition | signed-in/no-workspace stranded state, Google OAuth config mismatch | Hardened in code, console follow-up required |
| iOS ↔ Android parity | `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, Firebase config files | none beyond compile/test smoke | compare native config, console app registrations, signed build smoke tests | App Check policy drift, OAuth client mismatch, permission drift | Partially hardened |
| UI/UX, localization, RTL | `lib/app/`, `lib/features/settings/`, `lib/features/reports/` | onboarding localization, settings, reports tests, sync notice widget test | Arabic navigation, chart labels, back navigation smoke | chart readability in RTL, broader Arabic copy review | Mostly stable, needs manual pass |
| Performance & observability | `lib/main.dart`, list screens, reports, upload flows | widget/integration coverage for some list/nav paths | observe cold start, queue drain, voice timing, list pagination | missing breadcrumbs on critical flows, long-running operation opacity | Telemetry added |

## Severity-Ranked Findings

### P0

1. Android Google Sign-In release risk from OAuth client mismatch
   - Evidence: `android/app/google-services.json` contains `com.ahmed.buildozer`, but that client has only `client_type: 3` and no Android OAuth `client_type: 1`.
   - Expected: active Android package should have an Android OAuth client bound to package + SHA certificates.
   - Actual: only legacy package `com.buildtrack.buildtrack_app` has Android OAuth client registration in repo config.
   - Affected platforms: Android signed builds, Google Sign-In.
   - Required fix: regenerate Firebase Android client config after adding correct Android OAuth clients for `com.ahmed.buildozer`.
   - Required test: debug + signed Android Google Sign-In smoke test.
   - Owner: Firebase Console + mobile release configuration.

### P1

1. Queued sync failures were previously classified from string messages only
   - Reproduction: any queued callable failure stored only `toString()` output; downstream dead-letter notice had no reliable error code.
   - Expected: queue preserves normalized error code and message, and dead-letter UX reflects the real cause.
   - Actual before fix: quota/auth/archive failures could be mislabeled as generic.
   - Affected platforms: iOS + Android offline flows.
   - Fix status: fixed in repo by preserving `lastErrorCode` and using shared sync error classification.
   - Required automated test: queue dead-letter regression test.

2. Session restore could strand authenticated users without a resolved workspace
   - Reproduction: authenticated user opens app with no membership doc and no immediately usable workspace resolution from Firestore.
   - Expected: restore should deterministically recover workspace context or bootstrap it.
   - Actual before fix: restore returned `null`, leaving the signed-in user routed back through splash/features flow.
   - Affected platforms: iOS + Android auth restore, voice review restore path.
   - Fix status: fixed in repo with callable bootstrap fallback.
   - Required automated test: manual auth restore smoke plus router/session verification.

3. iOS debug App Check parity was weaker than Android
   - Reproduction: Apple debug builds skipped App Check activation while Android debug builds explicitly activated debug App Check.
   - Expected: mobile debug platforms should follow an explicit, auditable App Check strategy.
   - Actual before fix: Apple debug activation relied on a skip branch.
   - Affected platforms: iOS debug, callable/storage auth parity.
   - Fix status: fixed in repo with explicit `AppCheckActivationMode`.
   - Required automated test: strategy unit tests.

### P2

1. Release readiness still depends on external Firebase Console checks
   - Evidence: repo cannot prove App Check provider registration, OAuth SHA coverage, or RevenueCat webhook/dashboard alignment.
   - Required fix: follow release gate checklist.

### P3

1. Observability gaps on long-running flows
   - Status before fix: cold start, offline drain, callable retries, and voice processing lacked consistent breadcrumbs.
   - Fix status: lightweight Crashlytics telemetry added in this pass.

## Remediation Implemented In This Pass

- Added structured sync failure preservation and classification for offline replay.
- Added dead-letter notice distinctions for quota, auth, invalid target, and permission failures.
- Added explicit App Check activation strategy with debug Apple parity and test coverage.
- Added session-restore fallback bootstrap via callable function.
- Added splash-screen and router regression coverage for signed-in/no-workspace recovery.
- Moved offline sync dead-letter snackbars onto the app localization layer.
- Added Crashlytics breadcrumbs/timing for startup, queue drain, callable usage, and voice processing.
- Added audit/release documentation for repo and console follow-through.

## Remaining Release Blockers

- Regenerate `android/app/google-services.json` after fixing Firebase Android OAuth clients for `com.ahmed.buildozer`.
- Verify Firebase Console App Check providers and RevenueCat webhook/dashboard alignment.
- Run signed mobile smoke tests outside this Windows repo environment.
