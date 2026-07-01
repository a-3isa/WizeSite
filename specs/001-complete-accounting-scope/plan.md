# Implementation Plan: Complete Accounting Scope

**Branch**: `001-complete-accounting-scope` | **Date**: 2026-05-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-complete-accounting-scope/spec.md`

## Summary

Complete the original accounting/product-management scope inside the existing BuildTrack Flutter + Firebase application. The implementation extends the current expense, payment, attachment, entity, report, dashboard, offline queue, and test systems instead of rebuilding them. The plan prioritizes current regressions, accounting correctness, offline safety, scalable summary data, role-restricted financial access, and full coverage of the verified missing product areas.

## Technical Context

**Language/Version**: Dart SDK `^3.10.8`, Flutter app, TypeScript Cloud Functions

**Primary Dependencies**: Flutter, Riverpod, GoRouter, Firebase Auth, Cloud Firestore, Cloud Functions, Firebase Storage, Firebase Messaging, Firebase Crashlytics, Firebase App Check, Hive/Hive Flutter, connectivity_plus, file_picker, image_picker, pdf, printing, url_launcher, fake_cloud_firestore, mocktail

**Storage**: Cloud Firestore for workspace/project/accounting records and maintained summaries; Firebase Storage for attachment files; Hive/local storage for offline queue and local pending attachment references; Cloud Functions for backend mutation/summary maintenance where needed

**Testing**: `flutter analyze`, `flutter test`, focused widget/provider/repository tests, fake_cloud_firestore tests, functions `npm test`, Firestore emulator tests where available

**Target Platform**: Flutter mobile-first app with Android/iOS and generated desktop platform folders present; Firebase backend

**Project Type**: Existing mobile app with Firebase backend and serverless functions

**Performance Goals**: Normal list/filter/group/dashboard/aggregation interactions should complete without visible loading beyond 2 seconds for at least 95% of checks against a representative dataset of 5 projects, 100 entities, 2,000 expenses, 1,000 payments, and 500 attachment metadata records; reports should use bounded date ranges; list screens must remain paginated

**Constraints**: Preserve existing working behavior; do not store binary/base64 attachment content in Firestore; support offline transaction and attachment metadata save; restrict financial reports/balances/attachments to owner/admin/accounting-approved roles; no unbounded historical reads on normal screens; maintain backward compatibility for old records

**Scale/Scope**: Full original accounting scope across expenses, payments, suppliers/entities, workers, contractors, transport, equipment, reports, dashboard, quick entry, summaries, offline sync, indexes/rules, and tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The repository constitution defines enforceable project gates for existing behavior, accounting correctness, test-backed change discipline, offline/security recovery, and scalable data access. This feature uses those principles as the controlling quality bar:

- Preserve existing working systems and data compatibility.
- Fix active regressions before expanding behavior.
- Use test-first or test-backed implementation for high-risk accounting changes.
- Avoid full historical reads on normal screens.
- Keep financial data and attachments role-restricted.
- Keep offline sync recoverable and protected from double counting.

**Initial Gate Result**: PASS. The plan preserves existing behavior, requires test-backed accounting changes, defines offline/security recovery, and avoids unbounded normal-screen reads.

## Project Structure

### Documentation (this feature)

```text
specs/001-complete-accounting-scope/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── accounting-scope.openapi.yaml
└── tasks.md
```

### Source Code (repository root)

```text
lib/
├── app/
│   ├── localization/
│   └── router.dart
├── core/
│   ├── constants/
│   ├── models/
│   ├── providers/
│   ├── services/
│   └── widgets/
└── features/
    ├── add/
    ├── dashboard/
    ├── entities/
    ├── expenses/
    ├── payments/
    ├── projects/
    ├── reports/
    ├── settings/
    └── workers/

functions/
├── src/
│   ├── index.ts
│   ├── types/
│   └── utils/
└── lib/

test/
├── core/
├── features/
├── integration/
└── widget/

firestore.indexes.json
firestore.rules
pubspec.yaml
functions/package.json
```

**Structure Decision**: Continue with the existing feature-first Flutter structure under `lib/features`, shared models/services/widgets under `lib/core`, Cloud Functions under `functions/src`, and tests mirrored under `test/core`, `test/features`, and `test/widget`. Add new domains such as contractors/equipment/accounting sections as feature folders only when needed by implementation tasks.

## Complexity Tracking

No constitution violation requires justification. The feature is broad, but the complexity comes from completing an already requested product scope and preserving existing systems rather than adding unrelated architecture.

## Phase 0: Research Summary

See [research.md](./research.md). All planning unknowns were resolved into concrete decisions:

- Stabilize current failing tests first.
- Use maintained summary records for normal dashboard/aggregation views.
- Use bounded exact recalculation for date-scoped reports.
- Save transactions plus local attachment references offline and upload attachments after reconnect.
- Enforce owner/admin/accounting-approved access for financial reports, entity balances, and attachments.
- Use last-saved-change-wins for offline conflicts.
- Add missing domains without replacing current expense/payment flows.

## Phase 1: Design Summary

See [data-model.md](./data-model.md), [quickstart.md](./quickstart.md), and [contracts/accounting-scope.openapi.yaml](./contracts/accounting-scope.openapi.yaml).

The design centers on backward-compatible extensions to existing records, maintained summary documents for dashboards/aggregation, explicit attachment lifecycle states, role-gated financial read/export surfaces, and scoped report requests.

## Post-Design Constitution Check

**Result**: PASS.

- The design preserves existing project structure and working systems.
- Attachment data remains metadata-only in Firestore with files outside Firestore.
- Normal screens use pagination, scoped reads, or maintained summaries.
- Reports are bounded by date/filter request.
- Offline behavior has explicit pending, retry, synced, and failed states.
- Security requirements are explicit for financial reports, balances, exports, and attachments.
- Required tests are documented in quickstart and data-model validation expectations.
