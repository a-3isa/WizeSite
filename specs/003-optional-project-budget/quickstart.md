# Quickstart: Optional Project Budget

**Branch**: `003-optional-project-budget` | **Date**: 2026-08-17

How to verify this feature. Automated coverage comes first; the manual paths below exist because
constitution principle III requires a documented manual route wherever automation is unreliable
(notification delivery and offline sync both need the emulator or a device).

---

## Automated verification

```bash
# Dart analysis and tests
flutter analyze 2>&1 | Select-Object -First 80
flutter test --reporter compact

# Cloud Functions WITHOUT the emulator — the Firestore rules and
# project-recompute suites SKIP, which hides most of this feature's backend.
cd functions && npm test

# Cloud Functions WITH the emulator — run this one. It supplies
# FIRESTORE_EMULATOR_HOST automatically, so the rules and trigger suites
# actually execute. Requires the Firebase CLI and a JVM.
firebase emulators:exec --only firestore --project demo-wizesite "npm --prefix functions test"
```

Only the storage-rules suite still skips under the emulator command above; it needs
`FIREBASE_STORAGE_EMULATOR_HOST` and is unrelated to this feature.

Expect all three green before the feature is considered complete. Report any emulator-dependent
checks that were skipped rather than silently passing over them.

### Key automated cases

| Layer | Case |
|---|---|
| unit | `Project` derived getters — all four rows of the two-switch truth table |
| unit | `contractValue: 0` in a Firestore map resolves to `null`, not `0` |
| widget | project detail in expense-ledger mode — no revenue widgets, empty-state present |
| widget | project detail with contract — identical to pre-change baseline |
| widget | Budget-Limit-only project — budget bar shown, revenue side hidden |
| widget | project list card shows expenses, never "profit"/"loss", in expense-ledger mode |
| widget | Arabic locale renders every new string, RTL layout intact |
| functions | no contract → `riskLevel`/`healthStatus`/`remainingBalance` all null |
| functions | no contract → no `project_risk_alert` created, and any existing one deleted |
| functions | `budgetExceeded` still fires on a Budget-Limit-only project |
| functions | payment against contract-less project rejected |
| functions | clearing contract with a payment present rejected, project unchanged |
| functions | clearing contract with a zero-amount payment present still rejected |
| rules | null contract accepted; negative and zero rejected |

---

## Manual verification

### M1. Create without a budget (US1)

1. Projects → New Project.
2. Enter a name only. Leave Contract Value and Budget Limit empty.
3. Save.

Expect: created, no validation error, Contract Value not marked required.

### M2. Expense-ledger presentation (US2, US3)

1. Open the project from M1. Add two or three expenses.
2. Inspect project detail, the project list card, and the dashboard scoped to this project.

Expect on all three: no budget progress bar, no contract figure, no `0`/`0%` anywhere, no Add
Payment or View Payments action, no Total Income, no Profit Margin. The headline card shows total
expenses. The list card shows expenses and never says "profit" or "loss". An empty-state appears
where the revenue section would be, naming the reason and offering to set a Contract Value. No
layout gaps, orphaned headings, or empty cards.

### M3. Invariant — payment blocked (FR-037, FR-038)

1. Payments → Add Payment → open the project picker.

Expect: the M1 project is absent from the list.

### M4. Invariant — clear blocked (FR-039, FR-040)

1. Open any project that has a Contract Value and at least one payment.
2. Edit it, clear the Contract Value, save.

Expect: save is refused with a message naming the corrective action (remove the payments first).
Reopen the project and confirm nothing changed — contract intact, payments intact.

### M5. Restoring the revenue side (US5, FR-034)

1. Open the M1 project, edit it, enter a Contract Value, save.

Expect: budget widgets and revenue widgets both appear, and the budget bar reflects the expenses
already recorded from M2 rather than starting at 0%.

### M6. No false risk alerts (US4) — emulator

1. With the Firebase emulator running, add expenses to a contract-less project until expenses
   exceed anything it could plausibly earn.
2. Check the notifications collection for the affected members.

Expect: no `project_risk_alert`. Then set a Contract Value below the expense total and recompute —
the alert now appears, confirming suppression was conditional rather than removed.

### M7. Offline (US1-S3, FR-008, FR-041) — device or emulator

1. Go offline. Create a project with no budget values.

Expect: queued, shown optimistically, no `0` contract displayed.

2. Go online.

Expect: syncs cleanly, no queue rejection.

3. Offline again. On a project with a payment, try to clear the Contract Value.

Expect: rejected — at the client immediately, and if it reaches the queue, the server rejection
surfaces to the user rather than retrying silently.

### M8. Regression — contract-bearing projects (FR-018)

Open several existing projects that have Contract Values.

Expect: pixel-identical to pre-change behaviour. This is the check that matters most for
constitution principle I, and it is the reason the eighteen existing test files were updated rather
than deleted.

---

## Localization check

Switch the app to Arabic and repeat M2 and M4.

Expect: every new string is Arabic, none falls back to English, and RTL layout is correct. The
localization system falls back silently on a missing key, so a missed entry produces no error — it
just ships English to Arabic users. This check is the only thing that catches it.

**When editing `lib/app/localization/app_localizations.dart`, use the Edit tool only.** Passing this
file through PowerShell `Get-Content`/`Set-Content` corrupts its UTF-8 Arabic strings.
