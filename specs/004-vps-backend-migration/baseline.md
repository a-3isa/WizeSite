# Baseline Test Run (T011)

**Date**: 2026-09-30 | **Branch**: `004-vps-backend-migration` | **Status**: ✅ GREEN

| Suite | Initial | Final |
|---|---|---|
| `flutter analyze` | ✅ No issues | ✅ No issues |
| `flutter test` | ❌ 635 passed, 13 failed | ✅ 652 passed |
| `functions` lint | — | ✅ clean |
| `functions` tests (Firestore + Storage emulators) | ❌ 147 passed, 7 failed | ✅ 154 passed |
| `server` unit tests (new) | ✅ 2/2 | ✅ 2/2 |

All 20 initial failures came from uncommitted work already in the working tree when this branch was created
(audit-remediation changes), not from spec 004. Owner chose to fix them on this branch (option 1).

## Root causes and fixes

| # | Failing tests | Root cause | Fix | Kind |
|---|---|---|---|---|
| 1 | login / signup / verify-email failure paths (3) | `LocalSessionCleanup` opened a Hive box when Hive was never initialised; Hive 2 leaves the error on an un-awaited internal completer, so the test zone reports it even though the call catches it | `lib/core/services/local_session_cleanup.dart` only clears boxes that are already open (`main()` always opens them) + new test `sign-out cleanup never opens a box itself` | Code bug |
| 2 | splash routing (4) | New minimum-build gate always awaited `PackageInfo.fromPlatform()`, whose real async I/O never completes in widget tests, stalling session restore | `splash_screen.dart` reads the build number only when `minSupportedBuild > 0` (also skips platform I/O on the normal path) + new test for the update-required gate | Code bug |
| 3 | payments list / navigation / detail (6) | New financial role gate (matches `canAccessAccounting` in `firestore.rules`) is intended; tests supplied no role | Tests override `currentAccountingRoleProvider` with `owner` + new test: plain member sees the denied state | Stale tests |
| 4 | email invite (2, functions) | `ENFORCE_TEAM_MEMBER_LIMITS` flipped to `true` (audit F-D04) | Happy-path test uses a Pro workspace; quota test now asserts `LIMIT_REACHED` on free for both invite paths, then upgrades to Pro and verifies the legacy path | Stale tests |
| 5 | create expense/payment/worker-entry with attachments (3, functions) | New attachment hardening: download URL must be Firebase Storage; path must be `attachments|receipts/{uid}/…` | Fixtures use `firebasestorage.googleapis.com` URLs and `attachments/user_1/…` paths | Stale tests |
| 6 | recompute category totals (2, functions) | Server now keys labor cost as `worker` (deprecated `labor` merged) | Assertions read `categoryTotals.worker` | Stale tests |
| 6b | — (found while tracing #6) | **Real bug**: report offline overlay (`reports_providers.dart` `_mergeCategoryTotals`) still added queued worker entries under `labor`, so a report showed labor split across `worker` + `labor` | Overlay folds `labor` into `worker` for both server base and queued actions + new test `queued worker entries merge into the server worker category`; existing test updated | Code bug |
