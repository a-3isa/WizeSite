# Implementation Plan: Buildozer Review Improvement Pack

**Branch**: `001-review-improvement-pack` | **Date**: 2026-06-15 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-review-improvement-pack/spec.md`

## Summary

Complete the attached product-review recommendations as a gap-first improvement program inside the existing Buildozer Flutter and Firebase application. The implementation will preserve the accounting, offline, access-control, pagination, report-export, and subscription systems already in place while improving navigation, dashboard feedback, voice capture, transaction management, project/report scalability, entity directories, subscription clarity, authentication, sync recovery, accessibility, localization, and supporting code quality.

The work is delivered as independently testable user-story slices. Existing changes already present on the branch, including scoped custom-report export data, payment navigation context, entity-summary access gating, deterministic session restore, queue ordering, and removal of the three root artifacts, are treated as baseline behavior and must be regression-tested rather than reimplemented.

## Technical Context

**Language/Version**: Dart SDK `^3.10.8`, Flutter; TypeScript `^5.9.3` on Node.js 22 for Firebase Functions

**Primary Dependencies**: Flutter, Riverpod, GoRouter, Firebase Auth, Cloud Firestore, Cloud Functions, Firebase Storage, Firebase Messaging, Firebase Crashlytics, Firebase App Check, Hive, connectivity_plus, record, audioplayers, RevenueCat (`purchases_flutter` and `purchases_ui_flutter`), pdf, printing, fl_chart, intl, package_info_plus (planned)

**Storage**: Cloud Firestore for workspace, notification, project, worker, transaction, and maintained summary records; Hive for offline actions and local sync outcome visibility; Firebase Storage for attachments and voice uploads; bundled assets for branding and sign-in imagery

**Testing**: `flutter analyze`, `flutter test`, focused widget/provider/repository tests, fake_cloud_firestore, mocktail, functions `npm test`, and Firestore emulator-backed rules tests where available

**Target Platform**: Mobile-first Flutter application for Android and iOS, with existing generated desktop/web platform support preserved

**Project Type**: Existing Flutter mobile application with Firebase backend and serverless functions

**Performance Goals**: Primary navigation reacts immediately; dashboard and project/report scope changes show content or explicit progress within 3 seconds for at least 95% of checks; project and entity lists remain paginated; report exports remain project/date bounded and support more than 500 records through paging

**Constraints**: Preserve backward compatibility; maintain owner/admin/accounting-approved financial access; retain offline idempotency and last-saved-change-wins; avoid unbounded normal-screen reads; support Arabic and English including RTL; use live store pricing only; do not expose raw exception text; extend existing maintained backend data only where required for bounded summaries, deterministic ordering, recoverable typed mutations, data integrity, or access control

**Scale/Scope**: Four primary shell destinations, dashboard summaries and notifications, voice expense capture, expense/payment list behavior, projects, reports and exports, subscription/settings/authentication, sync status, workers and three entity directories, shared UI states, accessibility, localization, and related tests across the existing application

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Preserve Existing Product Behavior**: PASS. The design extends current feature folders and services, preserves existing report/payment fixes, and requires regression coverage before removing the old add launcher.
- **Accounting Correctness and Traceability**: PASS. Report scope remains project/date bounded, dashboard and project financial metrics stay role-gated, worker partial-payment totals require explicit paid amounts, exact worker totals come from a maintained full-worker summary, unresolved legacy partials are disclosed instead of estimated, and bulk transaction behavior uses existing archive mutations.
- **Test-Backed Change Discipline**: PASS. Every delivery slice defines focused automated tests, with current baseline verification recorded in `quickstart.md`.
- **Offline, Security, and Recovery First**: PASS. Sync status exposes failed items and conflict outcomes; retry behavior remains idempotent; notification read updates, maintained metric access, worker accounting summaries, and domain accounting writes require rules/functions coverage; financial access boundaries are preserved.
- **Scalable Data Access**: PASS. Active project streams are capped, list and selector flows paginate, financial project sorts use globally ordered `project_metrics` queries, dashboard reads one maintained workspace snapshot, entity directories depend on a resumable legacy-field backfill before ordered paging is enabled, and exports use bounded paging loops.

**Initial Gate Result**: PASS. No constitution exception is required.

## Project Structure

### Documentation (this feature)

```text
specs/001-review-improvement-pack/
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
|-- contracts/
|   |-- data-access-contract.md
|   `-- ui-behavior-contract.md
|-- checklists/
|   `-- requirements.md
`-- tasks.md                 # Created later by /speckit-tasks
```

### Source Code (repository root)

```text
lib/
|-- app/
|   |-- localization/
|   `-- router.dart
|-- core/
|   |-- constants/
|   |-- navigation/
|   |-- prefetch/
|   |-- providers/
|   |-- services/
|   |-- utils/
|   `-- widgets/
`-- features/
    |-- add/
    |-- auth/
    |-- common/
    |-- contractors/
    |-- dashboard/
    |-- entities/
    |-- equipment/
    |-- expenses/
    |-- notifications/
    |-- payments/
    |-- projects/
    |-- reports/
    |-- settings/
    |-- subscription/
    |-- transport/
    |-- voice_expense/
    `-- workers/

functions/
|-- src/
|-- lib/
`-- package.json

test/
|-- app/
|-- core/
|-- features/
|-- integration/
|-- localization/
|-- router/
|-- subscription/
`-- widget/

assets/branding/
firestore.rules
firestore.indexes.json
pubspec.yaml
```

**Structure Decision**: Continue the feature-first Flutter layout. Shared async-state, empty-state, and section presentation belongs under `lib/core/widgets`; feature-specific controllers and view models stay with their feature. Firebase work is limited to notification read-state rules/tests, accounting-only metric and domain-accounting rules, worker status and partial-payment validation, extension of the existing `workspace_metrics` recomputation, maintained `worker_accounting_summaries`, and idempotent admin migrations for missing entity ordering fields or worker-summary initialization. No parallel application or replacement architecture is introduced.

## Architecture Decisions

### Navigation and dashboard

- Expand the indexed shell to Home, Add, Reports, and Projects.
- Make `AddHubScreen` the canonical Add destination and retire the arc speed dial only after action parity, semantics, RTL, and navigation tests pass.
- Add a visible Resources section to `AddHubScreen` with direct entries for workers, contractors, equipment, and transport directories.
- Keep Notifications as a visible dashboard app-bar action with a bounded unread badge derived from the targeted notification feed.
- Extend the existing `workspace_metrics/{workspaceId}` recomputation with current-week totals, top values, category/labor/equipment/payment summaries, and bounded recent transaction references; build one `DashboardSnapshot` from that single maintained document plus the local pending queue overlay; and short-circuit dashboard financial providers for denied roles so Home still shows sync visibility, notifications, and non-financial quick actions without restricted metric reads.

### Financial capture and list management

- Model voice capture as an explicit state machine with a 60-second limit, elapsed/remaining time, live level visualization, production playback, localized errors, and user-currency defaults.
- Keep expense/payment pagination and filters, add removable filter tokens and small-screen sections, and use the existing archive mutations for the first safe bulk action.
- Keep export generation in existing PDF services and expose both print and share paths.

### Projects, reports, and entities

- Cap the active project warm stream and use repository paging for project screens and selectors; report selectors include archived projects through explicit paged queries. Recent/name sorts use project fields for every role, while expense/income/net sorts page globally through maintained `project_metrics` with stable tie-breakers before hydrating project documents and are shown only to accounting-authorized users.
- Use one report scope containing project and date range for all charts, tables, and exports.
- Preserve the existing paged custom-report data builder and add progress reporting and single-chart PDF sharing.
- Build contractor, equipment, and transport directories from the canonical `entities` collection, with paginated type filters and links to existing accounting detail routes. Run an idempotent cursor-batched admin backfill for missing `lastUsedAt` before enabling ordered directory paging.
- Add backward-compatible worker status values while preserving `isArchived` as the record visibility/lifecycle flag.
- Add optional `paidAmount` to worker accounting records only; require it for new partial records, derive paid/unpaid values deterministically, and visibly exclude unresolved legacy partials from confirmed balance totals.
- Maintain exact `worker_accounting_summaries` over the full worker ledger so totals do not depend on the visible page size.
- Replace direct widget writes in domain accounting screens with typed repository or mutation-adapter saves that expose visible pending and recoverable failure states; worker-specific partial-payment controls remain isolated to worker accounting.

### Account, subscription, and sync recovery

- Present only live RevenueCat offers; extend the package view model with real period/trial metadata and local feature-comparison content.
- Register local branding assets, keep the Google sign-in slot stable while support checks resolve, and rely on existing Firebase session restoration for low-friction return sign-in.
- Add a sync-status screen over the existing Hive queue, individual retry, and a persisted resolution outcome for last-saved conflict skips.
- Add app version/help/legal links in settings and retain explicit confirmation for diagnostic termination.

## Delivery Strategy

1. **Baseline and shared foundations**: preserve current passing behavior; introduce shared async/empty/error presentation and localization keys; add planned assets/dependencies.
2. **User Story 1**: shell navigation, notification unread state, dashboard ordering, refresh, summary composition, loading/error states, and upgrade placement.
3. **User Story 2**: voice capture, filter-token removal, compact filters, empty CTAs, bulk archive, export sharing, and payment context regression coverage.
4. **User Story 3**: project status/sort/metrics, bounded project access, report scope/export UX, chart empty/share behavior, entity directories, worker status/totals, and large-workspace checks.
5. **User Story 4**: plans, settings, login stability, sync status/retry/conflict visibility, offline banner transitions, and limit-reached upgrade clarity.
6. **Cross-cutting completion**: accessibility/RTL, localization audit, commented-code cleanup, shared-widget consolidation, analyzer/tests/functions tests, and documented manual device checks.

Each slice must produce working, testable software and may be committed independently. Task generation should use test-first steps for changed behavior and should not recreate baseline fixes already covered by passing tests.

## Requirement Coverage

- **User Story 1 / shell and dashboard**: FR-001 through FR-005A, FR-038 through FR-040, FR-044, FR-045, FR-050, FR-053, and FR-056.
- **User Story 2 / voice and transactions**: FR-006 through FR-014 and FR-043, including regression coverage for the already-implemented payment context fix.
- **User Story 3 / projects, reports, and resources**: FR-015 through FR-024, FR-041, FR-046, FR-047, and FR-052, including the already-implemented scoped/paged custom-report export builder.
- **User Story 4 / account, subscription, and sync**: FR-025 through FR-037A, FR-048, FR-049, FR-051, and FR-055.
- **Cross-cutting scope and cleanup**: FR-042 and FR-054 apply to every slice and constrain refactoring to work that supports the reviewed user outcomes.
- **Success criteria**: `quickstart.md` maps SC-001 through SC-016 to automated checks, a release-candidate state audit, timed performance runs, moderated usability cohorts, or the post-launch normalized support comparison. Post-launch SC-006 is tracked only through the release-evidence workflow and cannot be declared passed during implementation.

## Complexity Tracking

No constitution violation requires justification. The scope is broad because it translates a full product review, but the design remains within the existing Flutter/Firebase application, reuses current repositories and maintained summaries, and is decomposed into independent user-story slices.

## Post-Design Constitution Check

**Result**: PASS.

- Existing accounting and offline systems remain authoritative.
- New data fields have backward-compatible defaults.
- Dashboard, project, entity, and report reads have explicit bounds.
- Financial access gates remain role-based and are tested before data providers render.
- Notification and worker backend changes have explicit rules/functions tests.
- Automated and manual verification paths are documented in `quickstart.md`.
