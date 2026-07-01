# Quickstart: Complete Accounting Scope

This quickstart describes how to verify the planned implementation once tasks are generated and completed.

## 1. Baseline Checks

Run from `D:\WizeSite`:

```powershell
flutter analyze
flutter test
```

If full tests fail because of unrelated environment limits, run targeted suites and document the exact failure:

```powershell
flutter test test/core
flutter test test/features/expenses
flutter test test/features/payments
flutter test test/features/reports
flutter test test/features/dashboard
flutter test test/features/entities
flutter test test/widget
```

For Cloud Functions:

```powershell
cd functions
npm test
```

### Baseline Results

Record setup, foundational, and final verification command results here as the
implementation progresses.

| Checkpoint | Command | Result | Notes |
|------------|---------|--------|-------|
| Baseline | `flutter analyze` | PASS | No issues found |
| Baseline | `flutter test` | PASS | 103 tests passed |
| Baseline | `functions/npm test` | PASS | 7 passed, 2 emulator-dependent suites skipped because `FIRESTORE_EMULATOR_HOST` was not set |
| Setup | setup-phase regression commands | PASS | `voice_recorder_service_test.dart`, `add_entry_screen_test.dart`, and `prefill_and_sync_feedback_test.dart` passed |
| Foundational | `flutter analyze` | PASS | No issues found |
| Foundational | foundational targeted Flutter tests | PASS | 28 foundational tests passed for attachment lifecycle, access roles, offline action serialization, pending attachment service, storage upload service, and accounting summaries |
| Foundational | `functions/npm test` | PASS | TypeScript build passed; 7 Node tests passed, 2 emulator-dependent suites skipped because `FIRESTORE_EMULATOR_HOST` was not set |
| Final | `flutter analyze` | PASS | No issues found after worker-entry attachments, domain accounting screens, report request/export updates |
| Final | `flutter test` | PASS | 201 Flutter tests passed |
| Final | targeted feature tests | PASS | Worker attachment, report request/export/access, report provider, and domain accounting targeted suites passed |
| Final | `functions/npm test` | PASS | TypeScript build passed; 8 Node tests passed, 2 emulator-dependent suites skipped because `FIRESTORE_EMULATOR_HOST` was not set |
| Final | `dart run tool/release_audit.dart` | PASS | Android/iOS config checks passed, including Android OAuth client for `com.ahmed.buildozer` |

## 2. Required Implementation Order

1. Fix current failing tests and restore a trustworthy baseline.
2. Complete structured expense/payment fields and backward-compatible model parsing.
3. Implement offline transaction plus attachment-reference persistence and retry states.
4. Enforce role restrictions for reports, balances, exports, and attachments.
5. Add or complete entity persistence, recent suggestions, duplicate prevention, and missing entity domains.
6. Replace unbounded dashboard/entity aggregation reads with maintained summaries or scoped reads.
7. Complete filters, grouping, expense list row details, and quick summary cards.
8. Complete weekly dashboard summaries and export entry point.
9. Complete quick entry behavior and repeated values.
10. Complete modular PDF export types and section selection.
11. Add Firestore indexes/rules only for implemented query paths.
12. Fill automated tests and manual QA coverage.

## 3. Manual Verification Checklist

### Attachments

- Add expense with image.
- Add expense with PDF.
- Add payment with image/PDF.
- Add entity, worker, contractor, transport provider, and equipment provider attachments.
- Reject invalid attachment type.
- Reject oversized attachment.
- Save transaction with attachments offline and confirm pending upload state.
- Reconnect and confirm attachments upload and sync.
- Open attachment after saving.
- Preview and zoom image.
- Open/download PDF.
- Confirm list rows show attachment counts only.

### Expense Entry

- Create structured expense with category, entity, purpose, amount, date, payment method, payment status, notes, and attachments.
- Edit expense and confirm existing attachments/entity fields are preserved.
- Confirm old expense records still load with fallback fields.
- Confirm all required categories are available.

### Entity Suggestions

- Confirm suggestions appear after first use.
- Confirm duplicate normalized names are prevented or reused.
- Confirm recent entities appear first.
- Confirm autocomplete works in add expense, add payment, and quick entry.
- Confirm entity sync failure does not block transaction save.

### Filters/Search

- Filter expenses by entity, entity type, category, date range, project, payment method, and payment status.
- Search expenses by description, notes, supplier/entity name, and worker name.
- Filter payments by entity, entity type, date range, project, payment method, and payment status.
- Confirm active filter chips and clear-all behavior.
- Confirm no-results and failed-query states.

### Grouped Display

- Normal expense list.
- Group by exact date.
- Group by today/yesterday/current week/current month.
- Group by category.
- Group by entity.
- Group by payment method.
- Collapse/expand groups.
- Confirm group totals and counts.

### Summaries and Dashboard

- Confirm expenses page today, weekly, monthly, and transaction-count summaries.
- Confirm weekly dashboard expenses, payments, top entity, top category, labor, equipment, payment summary, recent transactions, and weekly export link.
- Confirm future-dated transactions outside week are excluded.
- Confirm maintained summaries avoid full historical loads.

### Entity Aggregation

- Confirm supplier/vendor, worker, contractor, transport, equipment, and other entity totals.
- Confirm total expenses, total payments, balance, count, attachment count, latest date, category breakdown, payment method breakdown, and transaction history.
- Confirm entity detail opens where implemented.

### PDF

- Export existing project report.
- Export expenses-only report.
- Export payments-only report.
- Export suppliers/entities report.
- Export workers report.
- Export contractors report.
- Export daily report.
- Export weekly report.
- Export filtered report.
- Export combined report with selected sections.
- Confirm empty reports do not crash and failed generation shows recoverable feedback.

### Offline/Permissions/Performance

- Create/update expenses and payments offline.
- Save attachments offline and sync after reconnect.
- Confirm last-saved-change-wins conflict behavior.
- Confirm pending actions appear once before and after sync.
- Confirm unauthorized users cannot view/export reports, balances, or attachments.
- Confirm pagination still works and indexes match actual queries.
- Confirm normal list, filter, grouping, dashboard, and aggregation interactions complete without visible loading beyond 2 seconds for at least 95% of checks using 5 projects, 100 entities, 2,000 expenses, 1,000 payments, and 500 attachment metadata records.

## 4. Minimum Automated Test Groups

- Attachment validation, metadata, offline pending upload, open/view fallbacks.
- Expense/payment create and update with attachments and all structured fields.
- Entity autocomplete, normalized duplicate prevention, recent-first ordering.
- Entity filtering and fallback name matching.
- Advanced filters and no-results states.
- Grouping/collapse totals and expansion behavior.
- Expense quick summary cards.
- Entity aggregation totals, breakdowns, and pending merge.
- Weekly dashboard totals, top values, and date bounds.
- Quick entry save-and-add-another and repeated values.
- PDF exporter for every report type and empty data.
- Offline queue merge, retry, dead-letter, conflict behavior, and pagination.
- Role restrictions for reports, balances, exports, and attachments.

## 5. Production Readiness Matrix

| Area | Status | Evidence | Remaining release action |
|------|--------|----------|--------------------------|
| Flutter static analysis | Ready | `flutter analyze` passed with no issues | None |
| Flutter automated tests | Ready | `flutter test` passed with 201 tests | None |
| Cloud Functions build/tests | Ready with emulator caveat | `npm test` passed; Firestore emulator suites skipped without `FIRESTORE_EMULATOR_HOST` | Run emulator-backed rules/recompute command before final production sign-off |
| Firebase deploy | Ready | `firebase deploy --only "functions,firestore:rules,firestore:indexes,storage" --config firebase.deploy.json` completed | Monitor first production worker-entry attachment saves |
| Android release config | Ready | `dart run tool/release_audit.dart` passed, including Android OAuth client for `com.ahmed.buildozer` | Run signed Google Sign-In smoke test |
| App Check | Needs console/device verification | Repo config and audit command pass local checks | Confirm Play Integrity, Apple provider, and debug tokens in Firebase Console |
| RevenueCat | Needs console/device verification | Repo tests and setup docs cover expected entitlement | Confirm `wizesite_pro`, offering, purchase, restore, and webhook in RevenueCat/Firebase |
| Mobile app release | Not shipped by Firebase deploy | Firebase backend deployed only | Build and distribute signed Android/iOS app binaries |
